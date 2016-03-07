#!/bin/bash

set -e

if [ "$TEST_SUITE" == "unit" ]; then
  echo "Exiting, no need for Cassandra"
  exit
fi

arr=(${CASSANDRA_HOSTS//,/ })

pip install --user PyYAML six
git clone https://github.com/pcmanus/ccm.git
pushd ccm
./setup.py install --user
popd
ccm create test -v binary:$CASSANDRA -n ${#arr[@]} -d
ccm start -v
ccm status
