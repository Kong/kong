#!/usr/bin/env bash
set -e

if [ ${TRAVIS_PULL_REQUEST} != "false" ]; then
  exit 0
fi

pushd kong-distributions
  VERSION=`dpkg-deb -f output/kong-enterprise-edition-*.xenial.all.deb Version`
  bash release.sh -u $BINTRAY_USER -k $BINTRAY_API_KEY -v ${VERSION} -p ubuntu:16.04 -c
popd


sudo mv kong-distributions/output/kong-*.tar.gz docker-kong-ee/alpine/kong.tar.gz

SOURCE_REPO=$(git config --get remote.origin.url)
SOURCE_COMMIT=$(git rev-parse HEAD)

pushd docker-kong-ee/alpine/
  sed -i -e '/apk update.*/a  && apk add gnupg \\' Dockerfile
  sed -i -e '/^USER kong/d' Dockerfile

  export KONG_ENTERPRISE_PACKAGE=kong.tar.gz

  docker build --no-cache \
    --label org.opencontainers.image.source="$SOURCE_REPO" \
    --label org.opencontainers.image.revision="$SOURCE_COMMIT" \
    --build-arg KONG_ENTERPRISE_PACKAGE=$KONG_ENTERPRISE_PACKAGE \
    -t kong-ee-dev .

  INT_REGISTRY=registry.kongcloud.io
  INT_PKG_IMAGE_TAG=$INT_REGISTRY/kong-ee-dev-master:latest
  docker tag kong-ee-dev $INT_PKG_IMAGE_TAG
  docker login $INT_REGISTRY -u kong-ee-deploy -p $INT_PKG_PASSWORD
  docker push $INT_PKG_IMAGE_TAG
popd
