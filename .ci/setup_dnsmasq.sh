#!/bin/bash

set -e

if [ "$TEST_SUITE" == "unit" ]; then
  echo "Exiting, no integration tests"
  exit
fi

mkdir -p $DNSMASQ_DIR

if [ ! "$(ls -A $DNSMASQ_DIR)" ]; then
  pushd $DNSMASQ_DIR
  wget http://www.thekelleys.org.uk/dnsmasq/dnsmasq-${DNSMASQ}.tar.gz
  tar xzf dnsmasq-${DNSMASQ}.tar.gz

  pushd dnsmasq-${DNSMASQ}
  make install DESTDIR=$DNSMASQ_DIR
  popd

  popd
fi
