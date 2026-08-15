#!/usr/bin/env bash
# Post-deploy smoke checks on the OVH host.
# Required: container + PROXY_NETWORK reachability (NPM path) + digest match when set.
# Public HTTPS is best-effort — Cloudflare often returns 403 to bots/datacenters
# unless /health is excepted from Bot Fight / WAF.
set -euo pipefail

PROXY_NETWORK="${PROXY_NETWORK:-web-proxy}"
PUBLIC_BASE_HOST="${PUBLIC_BASE_HOST:-zenora360.com}"

echo "== container /health =="
docker exec zenora-web wget -q -O - http://127.0.0.1:8080/health
echo

if [ -n "${IMAGE_DIGEST:-}" ]; then
  echo "== running image digest =="
  # Prefer Config.Image (compose sets repo@sha256:… on digest pulls).
  # RepoDigests can be empty right after recreate depending on engine/version.
  running_image="$(docker inspect -f '{{.Config.Image}}' zenora-web)"
  echo "Config.Image=${running_image}"
  case "${running_image}" in
    *"@${IMAGE_DIGEST}")
      echo "digest OK (${IMAGE_DIGEST})"
      ;;
    *)
      # Fallback: image object RepoDigests (when populated)
      matched=0
      image_id="$(docker inspect -f '{{.Image}}' zenora-web)"
      while IFS= read -r line; do
        [ -z "${line}" ] && continue
        case "${line}" in
          *"@${IMAGE_DIGEST}") matched=1 ;;
        esac
      done < <(docker image inspect -f '{{range .RepoDigests}}{{println .}}{{end}}' "${image_id}" 2>/dev/null || true)
      if [ "${matched}" -eq 1 ]; then
        echo "digest OK via RepoDigests (${IMAGE_DIGEST})"
      else
        echo "Running container is not at expected digest ${IMAGE_DIGEST}"
        docker image inspect -f '{{range .RepoDigests}}{{println .}}{{end}}' "${image_id}" || true
        exit 1
      fi
      ;;
  esac
fi

echo "== docker network ${PROXY_NETWORK} -> zenora-web:8080 =="
docker run --rm --network "${PROXY_NETWORK}" curlimages/curl:8.5.0 \
  -fsS --max-time 15 http://zenora-web:8080/health
echo
code="$(
  docker run --rm --network "${PROXY_NETWORK}" curlimages/curl:8.5.0 \
    -fsS -o /dev/null -w '%{http_code}' --max-time 15 http://zenora-web:8080/
)"
echo "GET / -> ${code}"
case "${code}" in
  200|301|302) ;;
  *)
    echo "Unexpected status from zenora-web on ${PROXY_NETWORK}: ${code}"
    exit 1
    ;;
esac

echo "== public https://${PUBLIC_BASE_HOST} (best-effort) =="
pub="$(
  curl -sS -o /dev/null -w '%{http_code}' --max-time 20 \
    -A 'Mozilla/5.0 (compatible; ZenoraDeploySmoke/1.0)' \
    "https://${PUBLIC_BASE_HOST}/health" || echo '000'
)"
echo "public /health -> ${pub}"
case "${pub}" in
  200)
    echo "Public edge OK"
    ;;
  403|503)
    echo "WARN: public edge returned ${pub} (often Cloudflare bot/WAF)."
    echo "Prefer a Cloudflare exception for path /health (see .github/README.md)."
    echo "Container + proxy-network checks passed; deploy is considered OK."
    ;;
  *)
    echo "WARN: unexpected public status ${pub}; container path is healthy."
    ;;
esac
