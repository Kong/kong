#!/bin/bash

set -e

CMD="busted -v -o gtest --exclude-tags=ci --repeat=3"

if [ "$TEST_SUITE" == "unit" ]; then
  CMD="$CMD --coverage spec/unit && luacov-coveralls -i kong"
elif [ "$TEST_SUITE" == "plugins" ]; then
  CMD="$CMD spec/plugins"
elif [ "$TEST_SUITE" == "integration" ]; then
  CMD="$CMD spec/integration"
fi

eval $CMD
