# syntax=docker/dockerfile:1
# =============================================================================
# ZENORA Web — Production image (multi-stage)
#
#   docker compose build web
#   docker compose up -d web
#   → http://localhost:8080
#
#   docker build -t zenora-web:local .
#   docker run --rm -p 8080:8080 zenora-web:local
# =============================================================================

# -----------------------------------------------------------------------------
# Stage 1 — Build the Vite SPA
# -----------------------------------------------------------------------------
FROM node:22-bookworm-slim AS builder

WORKDIR /app

ENV NPM_CONFIG_AUDIT=false \
    NPM_CONFIG_FUND=false \
    NPM_CONFIG_FETCH_RETRIES=5 \
    NPM_CONFIG_FETCH_RETRY_MINTIMEOUT=20000 \
    NPM_CONFIG_FETCH_RETRY_MAXTIMEOUT=120000 \
    NODE_OPTIONS=--max-old-space-size=4096

COPY package.json package-lock.json ./

# BuildKit cache keeps the npm store across builds (faster + more resilient).
RUN --mount=type=cache,target=/root/.npm \
    npm ci --ignore-scripts

COPY . .
RUN npm run build

# -----------------------------------------------------------------------------
# Stage 2 — Nginx serving static assets on :8080
# -----------------------------------------------------------------------------
FROM nginx:1.27-alpine AS production

ARG BUILD_DATE
ARG VCS_REF
ARG VERSION=latest

LABEL org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.source="https://github.com/zenora/zenora-web" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.vendor="ZENORA" \
      org.opencontainers.image.title="ZENORA Web" \
      org.opencontainers.image.description="ZENORA Digital Solutions Platform"

RUN apk upgrade --no-cache && \
    addgroup -g 1001 -S appgroup && \
    adduser -u 1001 -S appuser -G appgroup && \
    mkdir -p /tmp/nginx && \
    chown -R appuser:appgroup /tmp/nginx

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /app/dist /usr/share/nginx/html

RUN chown -R appuser:appgroup /usr/share/nginx/html && \
    chown -R appuser:appgroup /var/cache/nginx && \
    chown -R appuser:appgroup /var/log/nginx && \
    touch /var/run/nginx.pid && \
    chown appuser:appgroup /var/run/nginx.pid

USER 1001

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD ["wget", "--no-verbose", "--tries=1", "--spider", "http://127.0.0.1:8080/health"]

CMD ["nginx", "-g", "daemon off;"]
