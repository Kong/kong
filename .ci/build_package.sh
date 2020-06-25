#!/usr/bin/env bash
set -e

export KONG_DISTRIBUTIONS_VERSION=${KONG_DISTRIBUTIONS_VERSION:-master}
# Set silent build by default
export VERBOSE=${VERBOSE:-0}
# disable open tracing by default for master build (faster)
export ENABLE_OPENTRACING=${ENABLE_OPENTRACING:-0}

git clone -b ${KONG_DISTRIBUTIONS_VERSION} https://"$GITHUB_TOKEN"@github.com/Kong/kong-distributions.git || true
git clone https://"$GITHUB_TOKEN"@github.com/Kong/docker-kong-ee.git || true

pushd kong-distributions
  bash package.sh alpine

  # Set custom suffix for package ! This is no longer done in distributions
  # and for good reasons
  bash package.sh ubuntu:16.04 dev-${TRAVIS_BUILD_NUMBER}

  ls -l -1 output/kong-enterprise-edition-*.xenial.all.deb
  ls -l -1 output/kong-*.tar.gz
popd
