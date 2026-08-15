#!/usr/bin/env bash
# Remote deploy helper — executed on the OVH host via SSH from GitHub Actions.
# Expects: HARBOR_*, DEPLOY_APP_DIR, IMAGE_TAG, IMAGE_NAME
# Strongly recommended: IMAGE_DIGEST (sha256:...) — pull by digest when set
# Optional: IMAGE_TAR (gzipped docker save) — preferred when Harbor Cosign policy
#           blocks pulls (HTTP 412). Cosign verify still runs on the Actions runner.
# Optional: PROXY_NETWORK (default web-proxy)
set -euo pipefail

cd "${DEPLOY_APP_DIR}"

export COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-supply-chain}"
export PROXY_NETWORK="${PROXY_NETWORK:-web-proxy}"

PREVIOUS_IMAGE="$(docker inspect --format='{{.Config.Image}}' supply-chain-web 2>/dev/null || true)"
DEPLOY_MODE="registry"

TAG_REF="${HARBOR_REGISTRY}/${HARBOR_PROJECT}/${IMAGE_NAME}:${IMAGE_TAG}"

# Prefer digest for immutable pull; fall back to tag only if digest missing.
if [ -n "${IMAGE_DIGEST:-}" ]; then
  case "${IMAGE_DIGEST}" in
    sha256:*) ;;
    *)
      echo "IMAGE_DIGEST must start with sha256: (got: ${IMAGE_DIGEST})"
      exit 1
      ;;
  esac
  DIGEST_REF="${HARBOR_REGISTRY}/${HARBOR_PROJECT}/${IMAGE_NAME}@${IMAGE_DIGEST}"
else
  echo "WARN: IMAGE_DIGEST empty — weaker than digest pinning."
  DIGEST_REF="${TAG_REF}"
fi

# Default compose image ref (registry digest). Artifact mode overrides to TAG_REF.
IMAGE_REF="${DIGEST_REF}"

cleanup_harbor_login() {
  docker logout "${HARBOR_REGISTRY}" >/dev/null 2>&1 || true
}
trap cleanup_harbor_login EXIT

if [ -n "${IMAGE_TAR:-}" ] && [ -f "${IMAGE_TAR}" ]; then
  DEPLOY_MODE="artifact"
  echo "Loading image from artifact ${IMAGE_TAR} (bypasses Harbor pull / Cosign 412)"
  case "${IMAGE_TAR}" in
    *.gz|*.tgz) gzip -dc "${IMAGE_TAR}" | docker load ;;
    *) docker load -i "${IMAGE_TAR}" ;;
  esac
  if ! docker image inspect "${TAG_REF}" >/dev/null 2>&1; then
    echo "After docker load, expected tag ${TAG_REF} was not present."
    docker images
    exit 1
  fi
  IMAGE_REF="${TAG_REF}"
  echo "Artifact image ready: ${IMAGE_REF} (signed digest ${IMAGE_DIGEST:-n/a})"
fi

cat > .env <<EOF
HARBOR_REGISTRY=${HARBOR_REGISTRY}
HARBOR_PROJECT=${HARBOR_PROJECT}
IMAGE_NAME=${IMAGE_NAME}
IMAGE_TAG=${IMAGE_TAG}
IMAGE_DIGEST=${IMAGE_DIGEST:-}
IMAGE_REF=${IMAGE_REF}
COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT_NAME}
PROXY_NETWORK=${PROXY_NETWORK}
EOF

if [ "${DEPLOY_MODE}" = "registry" ]; then
  echo "${HARBOR_PASSWORD}" | docker login "${HARBOR_REGISTRY}" -u "${HARBOR_USERNAME}" --password-stdin
  echo "Pulling ${IMAGE_REF}"
  if ! pull_out="$(docker compose pull web 2>&1)"; then
    echo "${pull_out}"
    if echo "${pull_out}" | grep -Eqi '412|PROJECTPOLICYVIOLATION|not signed by cosign|Precondition Failed'; then
      echo ""
      echo "Harbor refused the pull (HTTP 412 / Cosign project policy)."
      echo "Auto-deploy from Release should use the release-image artifact instead."
      echo "Or: Harbor → Project → Configuration → Deployment security → disable Cosign."
    fi
    exit 1
  fi
fi

if ! docker network inspect "${PROXY_NETWORK}" >/dev/null 2>&1; then
  echo "Docker network '${PROXY_NETWORK}' not found."
  echo "Create it (or point PROXY_NETWORK at your Nginx Proxy Manager network), then retry."
  docker network ls
  exit 1
fi

# container_name conflicts if an older container exists outside this compose project.
if docker inspect supply-chain-web >/dev/null 2>&1; then
  project_label="$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project"}}' supply-chain-web 2>/dev/null || true)"
  service_label="$(docker inspect -f '{{index .Config.Labels "com.docker.compose.service"}}' supply-chain-web 2>/dev/null || true)"
  if [ "${project_label}" != "${COMPOSE_PROJECT_NAME}" ] || [ "${service_label}" != "web" ]; then
    echo "Removing orphaned container supply-chain-web (project='${project_label}' service='${service_label}')"
    docker rm -f supply-chain-web
  fi
fi

docker compose up -d --force-recreate --remove-orphans web

check_health() {
  docker exec supply-chain-web wget --no-verbose --tries=1 --spider "http://127.0.0.1:8080/health" >/dev/null 2>&1
}

wait_healthy() {
  local label="$1"
  local healthy=0
  for _ in $(seq 1 24); do
    if check_health; then
      healthy=1
      break
    fi
    sleep 5
  done
  if [ "${healthy}" -eq 1 ]; then
    echo "${label}: healthy"
    return 0
  fi
  echo "${label}: unhealthy"
  return 1
}

if ! wait_healthy "deploy"; then
  echo "Deployment healthcheck failed (container :8080/health)."
  docker ps -a --filter name=supply-chain-web --no-trunc || true
  docker logs --tail 80 supply-chain-web || true

  if [ -n "${PREVIOUS_IMAGE}" ] && [ "${PREVIOUS_IMAGE}" != "${IMAGE_REF}" ]; then
    echo "Rolling back to ${PREVIOUS_IMAGE}"
    cat > .env <<EOF
HARBOR_REGISTRY=${HARBOR_REGISTRY}
HARBOR_PROJECT=${HARBOR_PROJECT}
IMAGE_NAME=${IMAGE_NAME}
IMAGE_TAG=${IMAGE_TAG}
IMAGE_DIGEST=
IMAGE_REF=${PREVIOUS_IMAGE}
COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT_NAME}
PROXY_NETWORK=${PROXY_NETWORK}
EOF
    docker compose up -d --force-recreate web
    if wait_healthy "rollback"; then
      echo "rollback healthy — previous image is serving; new deploy rejected."
    else
      echo "rollback failed — previous image did not become healthy."
      docker logs --tail 80 supply-chain-web || true
    fi
  else
    echo "No previous image available for rollback."
  fi
  exit 1
fi

mkdir -p .deploy
{
  echo "deployed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "image_tag=${IMAGE_TAG}"
  echo "image_digest=${IMAGE_DIGEST:-}"
  echo "image_ref=${IMAGE_REF}"
  echo "deploy_mode=${DEPLOY_MODE}"
  echo "previous_image=${PREVIOUS_IMAGE}"
  echo "proxy_network=${PROXY_NETWORK}"
} > ".deploy/last-success.env"

# Export for smoke-test in the same SSH session
export DEPLOY_MODE
export IMAGE_REF

docker image prune -f
echo "Deployment healthy on network ${PROXY_NETWORK} (${IMAGE_REF}, mode=${DEPLOY_MODE})."
