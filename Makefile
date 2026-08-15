.PHONY: compose-up compose-down health

compose-up:
	WEB_HOST_PORT=8080 docker compose -f docker-compose.yml -f docker-compose.local.yml up -d --build web

compose-down:
	docker compose -f docker-compose.yml -f docker-compose.local.yml down

health:
	curl -fsS http://127.0.0.1:8080/health
