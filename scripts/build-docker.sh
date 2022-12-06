#!/usr/bin/env bash

set -e

source .requirements
source scripts/backoff.sh

DOWNLOAD_CACHE=${DOWNLOAD_CACHE:-/tmp}
KONG_VERSION=$(bash scripts/grep-kong-version.sh)
DOCKER_REPOSITORY=${TESTING_DOCKER_REPOSITORY:-"kong/kong-gateway-internal-testing"}
ARCHITECTURE=${ARCHITECTURE:-amd64}
KONG_CONTAINER_TAG=${KONG_CONTAINER_TAG:-$KONG_VERSION}
PACKAGE_TYPE=${PACKAGE_TYPE:-deb}
DOCKER_KONG_VERSION=${DOCKER_KONG_VERSION:-master}
BASE_IMAGE_NAME=${BASE_IMAGE_NAME:-"ubuntu:22.04"}

KONG_IMAGE_NAME=$DOCKER_REPOSITORY:$KONG_CONTAINER_TAG

DOCKER_BUILD_ARGS=()

if [ ! -d $DOWNLOAD_CACHE/docker-kong ]; then
  git clone https://github.com/Kong/docker-kong.git $DOWNLOAD_CACHE/docker-kong
fi

pushd $DOWNLOAD_CACHE/docker-kong
  git fetch
  git reset --hard $DOCKER_KONG_VERSION || git reset --hard origin/$DOCKER_KONG_VERSION
  chmod -R 755 ./*.sh
popd

if [ "$PACKAGE_TYPE" == "deb" ]; then
  cp bazel-bin/pkg/kong_${KONG_VERSION}_${ARCHITECTURE}.deb $DOWNLOAD_CACHE/docker-kong/kong.deb
fi

pushd $DOWNLOAD_CACHE/docker-kong
  DOCKER_BUILD_ARGS+=(--pull)
  DOCKER_BUILD_ARGS+=(--build-arg ASSET=local .)

  if [[ "$EDITION" == 'enterprise' ]]; then
    DOCKER_BUILD_ARGS+=(--build-arg EE_PORTS="8002 8445 8003 8446 8004 8447")
  fi

  sed -i.bak 's/^FROM .*/FROM '${BASE_IMAGE_NAME}'/' Dockerfile.$PACKAGE_TYPE

  with_backoff docker build \
    --progress=auto \
    -t $KONG_IMAGE_NAME \
    -f Dockerfile.$PACKAGE_TYPE \
    --build-arg KONG_VERSION=$KONG_VERSION \
    "${DOCKER_BUILD_ARGS[@]}"

  echo "Kong image Name: $KONG_IMAGE_NAME"
popd
