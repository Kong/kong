#!/bin/bash

set -e

if [ "$TEST_SUITE" == "unit" ]; then
  kong config -c kong.yml -e TEST -s TEST
else
  kong config -c kong.yml -d $DATABASE -e TEST -s TEST
fi

createuser --createdb kong
createdb -U kong kong_tests

CMD="busted -v -o gtest --exclude-tags=ci"

if [ "$TEST_SUITE" == "unit" ]; then
  CMD="$CMD --coverage spec/unit && luacov-coveralls -i kong"
elif [ "$TEST_SUITE" == "plugins" ]; then
  CMD="$CMD spec/plugins"
elif [ "$TEST_SUITE" == "integration" ]; then
  CMD="$CMD spec/integration"
fi

eval $CMD
