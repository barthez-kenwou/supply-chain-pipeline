APP_NAME := zenora-web
LOCAL_PORT ?= 8080

.PHONY: install lint typecheck test build validate docker-build docker-build-runtime docker-run compose-up compose-up-runtime compose-build

install:
	npm ci

lint:
	npm run lint

typecheck:
	npm run typecheck

test:
	npm run test

build:
	npm run build

validate:
	npm run ci:validate

docker-build:
	DOCKER_BUILDKIT=1 docker build -t $(APP_NAME):local .

docker-build-runtime:
	DOCKER_BUILDKIT=1 docker build -f Dockerfile.runtime -t $(APP_NAME):local .

docker-run:
	docker run --rm -p $(LOCAL_PORT):8080 $(APP_NAME):local

compose-build:
	docker compose build web

compose-up:
	WEB_HOST_PORT=$(LOCAL_PORT) IMAGE_REF=zenora-web:local docker compose -f docker-compose.yml -f docker-compose.local.yml up -d --build web

compose-up-runtime:
	WEB_HOST_PORT=$(LOCAL_PORT) IMAGE_REF=zenora-web:local DOCKERFILE=Dockerfile.runtime docker compose -f docker-compose.yml -f docker-compose.local.yml up -d --build web
