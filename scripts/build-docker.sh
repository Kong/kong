#!/usr/bin/env bash

set -e

# This script is from the Kong/kong-build-tools repo, and is used to build the Kong Docker image.

source .requirements
source scripts/backoff.sh

KONG_VERSION=$(bash scripts/grep-kong-version.sh)

DOCKER_REPOSITORY=${DOCKER_REPOSITORY:-"kong/kong"}
ARCHITECTURE=${ARCHITECTURE:-amd64}
KONG_CONTAINER_TAG=${KONG_CONTAINER_TAG:-$KONG_VERSION}
PACKAGE_TYPE=${PACKAGE_TYPE:-deb}
KONG_BASE_IMAGE=${KONG_BASE_IMAGE:-}

ARTIFACT_PREFIX=${ARTIFACT_PREFIX:-"bazel-bin/pkg"}
ARTIFACT=${ARTIFACT:-"kong.deb"}

KONG_ARTIFACT=$ARTIFACT_PREFIX/$ARTIFACT
KONG_IMAGE_NAME=$DOCKER_REPOSITORY:$KONG_CONTAINER_TAG

BUILD_ARGS=()
if [ "$EDITION" == 'enterprise' ]; then
  BUILD_ARGS+=(--build-arg EE_PORTS="8002 8445 8003 8446 8004 8447")
fi

if [ -n "$KONG_BASE_IMAGE" ]; then
  BUILD_ARGS+=(--build-arg KONG_BASE_IMAGE="$KONG_BASE_IMAGE")
fi

docker_build () {
  tar -czh $KONG_ARTIFACT build/dockerfiles LICENSE | docker build \
    --pull \
    --progress=auto \
    -t $KONG_IMAGE_NAME \
    -f build/dockerfiles/$PACKAGE_TYPE.Dockerfile \
    --build-arg KONG_VERSION="$KONG_VERSION" \
    --build-arg KONG_ARTIFACT="$KONG_ARTIFACT" \
    "${BUILD_ARGS[@]}" -
}

with_backoff docker_build

echo "Kong image Name: $KONG_IMAGE_NAME"
