#!/usr/bin/env bash
set -e

export BUSTED_ARGS="-o gtest -v --exclude-tags=flaky,ipv6"

if [ "$KONG_TEST_DATABASE" == "postgres" ]; then
    export KONG_TEST_PG_DATABASE=travis
    export KONG_TEST_PG_USER=postgres
    export KONG_TEST_PG_DATABASE=travis
    export TEST_CMD="bin/busted $BUSTED_ARGS,cassandra"
    eval "$TEST_CMD" spec/02-integration/
    eval "$TEST_CMD" spec/03-plugins/
    eval "$TEST_CMD" spec-old-api/02-integration/
    eval "$TEST_CMD" spec-old-api/03-plugins/
elif [ "$KONG_TEST_DATABASE" == "cassandra" ]; then
    export KONG_TEST_CASSANDRA_KEYSPACE=kong_tests
    export KONG_TEST_DB_UPDATE_PROPAGATION=1
    export TEST_CMD="bin/busted $BUSTED_ARGS,postgres"
    eval "$TEST_CMD" spec/02-integration/
    eval "$TEST_CMD" spec/03-plugins/
fi