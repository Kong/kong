#!/usr/bin/env bash
set -e

export BUSTED_ARGS="-o gtest -v --exclude-tags=flaky,ipv6"
export TEST_CMD="bin/busted $BUSTED_ARGS"

createuser --createdb kong
createdb -U kong kong_tests

if [ "$TEST_SUITE" == "lint" ]; then
    make lint
elif [ "$TEST_SUITE" == "unit" ]; then
    make test
elif [ "$TEST_SUITE" == "integration" ]; then
    make test-integration
elif [ "$TEST_SUITE" == "plugins" ]; then
    make test-plugins
elif [ "$TEST_SUITE" == "pdk" ]; then
    TEST_NGINX_RANDOMIZE=1 prove -I. -j$JOBS -r t/01-pdk
elif [ "$TEST_SUITE" == "old-unit" ]; then
    make old-test
elif [ "$TEST_SUITE" == "old-integration" ]; then
    make old-test-integration
elif [ "$TEST_SUITE" == "old-plugins" ]; then
    make old-test-plugins
fi
