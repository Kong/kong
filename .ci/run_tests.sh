#!/usr/bin/env bash
set -e

export BUSTED_ARGS="-o gtest -v --exclude-tags=ci"
export TEST_CMD="bin/busted $BUSTED_ARGS"

createuser --createdb kong
createdb -U kong kong_tests

if [ "$TEST_SUITE" == "lint" ]; then
    make lint &>> build.log || (cat build.log && exit 1)
elif [ "$TEST_SUITE" == "unit" ]; then
    make test &>> build.log || (cat build.log && exit 1)
elif [ "$TEST_SUITE" == "integration" ]; then
    make test-integration &>> build.log || (cat build.log && exit 1)
elif [ "$TEST_SUITE" == "plugins" ]; then
    make test-plugins &>> build.log || (cat build.log && exit 1)
fi
