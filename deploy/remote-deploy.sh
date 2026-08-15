#!/usr/bin/env bash
# Remote deploy helper — executed on the OVH host via SSH from GitHub Actions.
# Expects: HARBOR_*, DEPLOY_APP_DIR, IMAGE_TAG, IMAGE_NAME
# Strongly recommended: IMAGE_DIGEST (sha256:...) — pull by digest when set
# Optional: PROXY_NETWORK (default web-proxy)
set -euo pipefail

cd "${DEPLOY_APP_DIR}"

export COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-zenora}"
export PROXY_NETWORK="${PROXY_NETWORK:-web-proxy}"

PREVIOUS_IMAGE="$(docker inspect --format='{{.Config.Image}}' zenora-web 2>/dev/null || true)"

# Prefer digest for immutable pull; fall back to tag only if digest missing.
if [ -n "${IMAGE_DIGEST:-}" ]; then
  case "${IMAGE_DIGEST}" in
    sha256:*) ;;
    *)
      echo "IMAGE_DIGEST must start with sha256: (got: ${IMAGE_DIGEST})"
      exit 1
      ;;
  esac
  IMAGE_REF="${HARBOR_REGISTRY}/${HARBOR_PROJECT}/${IMAGE_NAME}@${IMAGE_DIGEST}"
else
  echo "WARN: IMAGE_DIGEST empty — pulling by tag ${IMAGE_TAG} (weaker than digest)."
  IMAGE_REF="${HARBOR_REGISTRY}/${HARBOR_PROJECT}/${IMAGE_NAME}:${IMAGE_TAG}"
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

if ! docker network inspect "${PROXY_NETWORK}" >/dev/null 2>&1; then
  echo "Docker network '${PROXY_NETWORK}' not found."
  echo "Create it (or point PROXY_NETWORK at your Nginx Proxy Manager network), then retry."
  docker network ls
  exit 1
fi

cleanup_harbor_login() {
  docker logout "${HARBOR_REGISTRY}" >/dev/null 2>&1 || true
}
trap cleanup_harbor_login EXIT

echo "${HARBOR_PASSWORD}" | docker login "${HARBOR_REGISTRY}" -u "${HARBOR_USERNAME}" --password-stdin

echo "Pulling ${IMAGE_REF}"
docker compose pull web

# container_name conflicts if an older container exists outside this compose project.
if docker inspect zenora-web >/dev/null 2>&1; then
  project_label="$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project"}}' zenora-web 2>/dev/null || true)"
  service_label="$(docker inspect -f '{{index .Config.Labels "com.docker.compose.service"}}' zenora-web 2>/dev/null || true)"
  if [ "${project_label}" != "${COMPOSE_PROJECT_NAME}" ] || [ "${service_label}" != "web" ]; then
    echo "Removing orphaned container zenora-web (project='${project_label}' service='${service_label}')"
    docker rm -f zenora-web
  fi
fi

docker compose up -d --force-recreate --remove-orphans web

check_health() {
  docker exec zenora-web wget --no-verbose --tries=1 --spider "http://127.0.0.1:8080/health" >/dev/null 2>&1
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
  docker ps -a --filter name=zenora-web --no-trunc || true
  docker logs --tail 80 zenora-web || true

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
      docker logs --tail 80 zenora-web || true
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
  echo "previous_image=${PREVIOUS_IMAGE}"
  echo "proxy_network=${PROXY_NETWORK}"
} > ".deploy/last-success.env"

docker image prune -f
echo "Deployment healthy on network ${PROXY_NETWORK} (${IMAGE_REF})."
