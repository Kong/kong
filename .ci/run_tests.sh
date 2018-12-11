#!/usr/bin/env bash
set -euo pipefail

export BUSTED_ARGS="-o gtest -v --exclude-tags=flaky,ipv6"

if [ "${KONG_TEST_DATABASE:-}" == "postgres" ]; then
    export TEST_CMD="bin/busted $BUSTED_ARGS,cassandra"
elif [ "${KONG_TEST_DATABASE:-}" == "cassandra" ]; then
    export KONG_TEST_CASSANDRA_KEYSPACE=kong_tests
    export KONG_TEST_DB_UPDATE_PROPAGATION=1
    export TEST_CMD="bin/busted $BUSTED_ARGS,postgres"
fi

if [ "$TEST_SUITE" == "integration" ]; then
    exec "$TEST_CMD" spec/02-integration/
elif [ "$TEST_SUITE" == "plugins" ]; then
    exec "$TEST_CMD" spec/03-plugins/
elif [ "$TEST_SUITE" == "old-integration" ]; then
    exec "$TEST_CMD" spec-old-api/02-integration/
elif [ "$TEST_SUITE" == "old-plugins" ]; then
    exec "$TEST_CMD" spec-old-api/03-plugins/
elif [ "$TEST_SUITE" == "pdk" ]; then
    exec env TEST_NGINX_RANDOMIZE=1 prove -I. -j$JOBS -r t/01-pdk
fi
