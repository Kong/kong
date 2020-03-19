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

  docker build --no-cache --build-arg KONG_ENTERPRISE_PACKAGE=$KONG_ENTERPRISE_PACKAGE -t kong-ee-dev .

  # XXX: remove once we are ok switching to github pkg registry
  DOCKER_HUB_IMAGE_TAG=mashape/kong-enterprise:dev-master
  docker tag kong-ee-dev $DOCKER_HUB_IMAGE_TAG
  docker login -u $DOCKER_USERNAME -p $DOCKER_PASSWORD
  docker push $DOCKER_HUB_IMAGE_TAG

  GITHUB_PKG_IMAGE_TAG=docker.pkg.github.com/kong/ee-dev-master/ee-dev-master:latest
  docker tag kong-ee-dev $GITHUB_PKG_IMAGE_TAG
  docker login docker.pkg.github.com -u notneeded -p $GITHUB_PKG_TOKEN
  docker push $GITHUB_PKG_IMAGE_TAG
popd
