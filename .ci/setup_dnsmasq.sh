#!/bin/bash

set -e

if [ "$TEST_SUITE" == "unit" ]; then
  echo "Exiting, no integration tests"
  exit
fi

mkdir -p $DNSMASQ_DIR

if [ ! "$(ls -A $DNSMASQ_DIR)" ]; then
  pushd $DNSMASQ_DIR
  wget http://www.thekelleys.org.uk/dnsmasq/dnsmasq-${DNSMASQ_VERSION}.tar.gz
  tar xzf dnsmasq-${DNSMASQ_VERSION}.tar.gz

  pushd dnsmasq-${DNSMASQ_VERSION}
  make install DESTDIR=$DNSMASQ_DIR
  popd

  popd
fi
