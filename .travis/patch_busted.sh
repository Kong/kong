#!/bin/bash

# Remove this file once a new Busted version has been released > rc9-0

cd /usr/local/share/lua/5.1/
wget https://github.com/o-lim/busted/commit/619891c008836914de48abe97c5229adc14f37f0.patch
sudo patch -p1 < 619891c008836914de48abe97c5229adc14f37f0.patch

cd $TRAVIS_BUILD_DIR