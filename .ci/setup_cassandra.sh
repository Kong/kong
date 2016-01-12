#!/bin/bash

set -e

arr=(${CASSANDRA_HOSTS//,/ })

pip install --user PyYAML six
git clone https://github.com/pcmanus/ccm.git
pushd ccm
./setup.py install --user
popd
ccm create test -v binary:$CASSANDRA_VERSION -n ${#arr[@]} -d
ccm start -v
ccm status
