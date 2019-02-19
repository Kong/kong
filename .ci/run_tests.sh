#!/usr/bin/env bash
set -e

export BUSTED_ARGS="-o gtest -v --exclude-tags=flaky,ipv6"

if [ "$KONG_TEST_DATABASE" == "postgres" ]; then
    export TEST_CMD="bin/busted $BUSTED_ARGS,cassandra,off"
elif [ "$KONG_TEST_DATABASE" == "cassandra" ]; then
    export KONG_TEST_CASSANDRA_KEYSPACE=kong_tests
    export KONG_TEST_DB_UPDATE_PROPAGATION=1
    export TEST_CMD="bin/busted $BUSTED_ARGS,postgres,off"
else
    export TEST_CMD="bin/busted $BUSTED_ARGS,postgres,cassandra,db"
fi

if [ "$TEST_SUITE" == "integration" ]; then
    eval "$TEST_CMD" spec/02-integration/
fi
if [ "$TEST_SUITE" == "dbless" ]; then
    eval "$TEST_CMD" spec/02-integration/02-cmd spec/02-integration/05-proxy
fi
if [ "$TEST_SUITE" == "plugins" ]; then
    eval "$TEST_CMD" spec/03-plugins/
fi
if [ "$TEST_SUITE" == "pdk" ]; then
    TEST_NGINX_RANDOMIZE=1 prove -I. -j$JOBS -r t/01-pdk
fi
