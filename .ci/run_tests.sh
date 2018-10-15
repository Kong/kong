#!/usr/bin/env bash
set -e

export BUSTED_ARGS="-o gtest -v --exclude-tags=flaky,ipv6"

if [ "$KONG_TEST_DATABASE" == "postgres" ]; then
    export KONG_TEST_PG_DATABASE=travis
    export KONG_TEST_PG_USER=postgres
    export KONG_TEST_PG_DATABASE=travis
    export TEST_CMD="bin/busted $BUSTED_ARGS,cassandra"
elif [ "$KONG_TEST_DATABASE" == "cassandra" ]; then
    export KONG_TEST_CASSANDRA_KEYSPACE=kong_tests
    export KONG_TEST_DB_UPDATE_PROPAGATION=1
    export TEST_CMD="bin/busted $BUSTED_ARGS,postgres"
fi

mkdir output
if [ "$TEST_SUITE" == "integration" ]; then
    eval "$TEST_CMD" spec/02-integration/ | tee output/integration.txt
fi
if [ "$TEST_SUITE" == "plugins" ]; then
    eval "$TEST_CMD" spec/03-plugins/ | tee output/plugins.txt
fi
if [ "$TEST_SUITE" == "old-integration" ]; then
    eval "$TEST_CMD" spec-old-api/02-integration/ | tee output/old_integration.txt
fi
if [ "$TEST_SUITE" == "old-plugins" ]; then
    eval "$TEST_CMD" spec-old-api/03-plugins/ | tee output/old_plugins.txt
fi
if [ "$TEST_SUITE" == "pdk" ]; then
    TEST_NGINX_RANDOMIZE=1 prove -I. -j$JOBS -r t/01-pdk | tee output/pdk.txt
fi
