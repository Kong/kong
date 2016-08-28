set -e

export BUSTED_ARGS="-o gtest -v --exclude-tags=ci"
export TEST_CMD="KONG_SERF_PATH=$SERF_INSTALL/serf bin/busted $BUSTED_ARGS"

if [ "$TEST_SUITE" == "lint" ]; then
  make lint
elif [ "$TEST_SUITE" == "unit" ]; then
  make test
else
  createuser --createdb kong
  createdb -U kong kong_tests

  if [ "$TEST_SUITE" == "integration" ]; then
    make test-integration
  elif [ "$TEST_SUITE" == "plugins" ]; then
    make test-plugins
  fi
fi
