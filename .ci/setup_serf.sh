#!/bin/bash

set -e

if [ "$TEST_SUITE" == "unit" ]; then
  echo "Exiting, no integration tests"
  exit
fi

mkdir -p $SERF_DIR

if [ ! "$(ls -A $SERF_DIR)" ]; then
  pushd $SERF_DIR
  wget https://releases.hashicorp.com/serf/${SERF_VERSION}/serf_${SERF_VERSION}_linux_amd64.zip
  unzip serf_${SERF_VERSION}_linux_amd64.zip
  popd
fi
