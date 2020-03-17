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
pushd docker-kong-ee/alpine/
  sed -i -e '/apk update.*/a  && apk add gnupg \\' Dockerfile
  sed -i -e '/^USER kong/d' Dockerfile

  export KONG_ENTERPRISE_PACKAGE=kong.tar.gz

  docker build --no-cache --build-arg KONG_ENTERPRISE_PACKAGE=$KONG_ENTERPRISE_PACKAGE -t mashape/kong-enterprise:"$DOCKER_TAG_NAME" .
popd
