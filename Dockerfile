# syntax=docker/dockerfile:1
# Minimal static demo image — proves the supply-chain path without an app monolith.
FROM nginx:1.27-alpine AS production

ARG BUILD_DATE
ARG VCS_REF
ARG VERSION=latest

LABEL org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.source="https://github.com/barthez-kenwou/supply-chain-pipeline" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.title="Supply Chain Demo" \
      org.opencontainers.image.description="Static demo for an OCI supply-chain pipeline"

RUN apk upgrade --no-cache || true; \
    addgroup -g 1001 -S appgroup && \
    adduser -u 1001 -S appuser -G appgroup && \
    mkdir -p /tmp/nginx && \
    chown -R appuser:appgroup /tmp/nginx

COPY app/nginx.conf /etc/nginx/conf.d/default.conf
COPY app/index.html app/styles.css app/app.js app/analytics.js app/plausible.js /usr/share/nginx/html/

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
