#!/usr/bin/env bash
set -e

export BUSTED_ARGS="-o gtest -v --exclude-tags=flaky"
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
fi
