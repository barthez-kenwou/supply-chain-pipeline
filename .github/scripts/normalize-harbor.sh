#!/usr/bin/env bash
# Normalize Harbor coordinates into a valid Docker image repository.
# Expects: HARBOR_REGISTRY, HARBOR_PROJECT, IMAGE_NAME
# Exports: HARBOR_REGISTRY, HARBOR_PROJECT, REPO
set -euo pipefail

trim() {
  printf '%s' "$1" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

registry="$(trim "${HARBOR_REGISTRY:-}")"
project="$(trim "${HARBOR_PROJECT:-}")"
image_name="$(trim "${IMAGE_NAME:-}")"

registry="${registry#http://}"
registry="${registry#https://}"
registry="${registry%/}"
project="${project#/}"
project="${project%/}"

registry="$(printf '%s' "$registry" | tr '[:upper:]' '[:lower:]')"
project="$(printf '%s' "$project" | tr '[:upper:]' '[:lower:]')"
image_name="$(printf '%s' "$image_name" | tr '[:upper:]' '[:lower:]')"

if [ -z "$registry" ] || [ -z "$project" ] || [ -z "$image_name" ]; then
  echo "Harbor coordinates incomplete after normalize (registry/project/image)."
  exit 1
fi

if [[ "$registry" == *"/"* ]]; then
  echo "HARBOR_REGISTRY must be a host[:port] only (no path, no https://)."
  echo "Example: harbor.example.com"
  exit 1
fi

if ! [[ "$registry" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?(:[0-9]+)?$ ]]; then
  echo "HARBOR_REGISTRY is not a valid Docker registry host."
  echo "Use: harbor.example.com   (no https://, no trailing slash, no spaces)"
  exit 1
fi

if ! [[ "$project" =~ ^[a-z0-9]+([._-][a-z0-9]+)*$ ]]; then
  echo "HARBOR_PROJECT is not a valid Docker path component."
  echo "Use lowercase (e.g. zenora). No spaces or uppercase."
  exit 1
fi

if ! [[ "$image_name" =~ ^[a-z0-9]+([._-][a-z0-9]+)*$ ]]; then
  echo "IMAGE_NAME is not a valid Docker repository name."
  exit 1
fi

HARBOR_REGISTRY="$registry"
HARBOR_PROJECT="$project"
REPO="${registry}/${project}/${image_name}"
export HARBOR_REGISTRY HARBOR_PROJECT REPO
