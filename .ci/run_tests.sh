#!/usr/bin/env bash
set -e

export BUSTED_ARGS=${BUSTED_ARGS:-"-o gtest -v --exclude-tags=flaky,ipv6"}

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
    eval "$TEST_CMD" spec/02-integration/02-cmd \
                     spec/02-integration/05-proxy \
                     spec/02-integration/04-admin_api/02-kong_routes_spec.lua \
                     spec/02-integration/04-admin_api/15-off_spec.lua
fi
if [ "$TEST_SUITE" == "plugins" ]; then
    eval "$TEST_CMD" spec/03-plugins/
fi
if [ "$TEST_SUITE" == "pdk" ]; then
    TEST_NGINX_RANDOMIZE=1 prove -I. -j$JOBS -r t/01-pdk
fi


# EE tests
if [ "$TEST_SUITE" == "unit-ee" ]; then
    make test-ee
elif [ "$TEST_SUITE" == "integration-ee" ]; then
    cd .ci/ad-server && make build-ad-server && make clone-plugin && cd ../..
    make test-integration-ee
elif [ "$TEST_SUITE" == "plugins-ee" ]; then
    make test-plugins-ee
fi
