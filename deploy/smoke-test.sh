#!/usr/bin/env bash
# Post-deploy smoke checks on the OVH host.
# Required: container + PROXY_NETWORK reachability (NPM path) + digest match when set.
# Public HTTPS is best-effort — Cloudflare often returns 403 to bots/datacenters
# unless /health is excepted from Bot Fight / WAF.
set -euo pipefail

PROXY_NETWORK="${PROXY_NETWORK:-web-proxy}"
PUBLIC_BASE_HOST="${PUBLIC_BASE_HOST:-example.com}"

echo "== container /health =="
docker exec supply-chain-web wget -q -O - http://127.0.0.1:8080/health
echo

if [ -n "${IMAGE_DIGEST:-}" ]; then
  echo "== running image digest =="
  running_image="$(docker inspect -f '{{.Config.Image}}' supply-chain-web)"
  echo "Config.Image=${running_image}"
  echo "DEPLOY_MODE=${DEPLOY_MODE:-registry}"

  if [ "${DEPLOY_MODE:-}" = "artifact" ]; then
    # Artifact path uses tag ref locally; trust chain is cosign verify (runner) +
    # release-image artifact from the same Release run as IMAGE_DIGEST.
    case "${running_image}" in
      *":${IMAGE_TAG}"|*":${IMAGE_TAG}@*"|"${IMAGE_TAG}")
        echo "artifact tag OK (${IMAGE_TAG}); expected signed digest ${IMAGE_DIGEST}"
        ;;
      *"@${IMAGE_DIGEST}")
        echo "digest OK (${IMAGE_DIGEST})"
        ;;
      *)
        echo "WARN: Config.Image=${running_image} (expected tag ${IMAGE_TAG}); continuing — digest pinned via Release artifact + cosign verify"
        ;;
    esac
  else
    case "${running_image}" in
      *"@${IMAGE_DIGEST}")
        echo "digest OK (${IMAGE_DIGEST})"
        ;;
      *)
        matched=0
        image_id="$(docker inspect -f '{{.Image}}' supply-chain-web)"
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
fi

echo "== docker network ${PROXY_NETWORK} -> supply-chain-web:8080 =="
docker run --rm --network "${PROXY_NETWORK}" curlimages/curl:8.5.0 \
  -fsS --max-time 15 http://supply-chain-web:8080/health
echo
code="$(
  docker run --rm --network "${PROXY_NETWORK}" curlimages/curl:8.5.0 \
    -fsS -o /dev/null -w '%{http_code}' --max-time 15 http://supply-chain-web:8080/
)"
echo "GET / -> ${code}"
case "${code}" in
  200|301|302) ;;
  *)
    echo "Unexpected status from supply-chain-web on ${PROXY_NETWORK}: ${code}"
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
