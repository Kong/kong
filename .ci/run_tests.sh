#!/usr/bin/env bash
set -ex

function cyan() {
    echo -e "\033[1;36m$*\033[0m"
}
function red() {
    echo -e "\033[1;31m$*\033[0m"
}

export BUSTED_ARGS="--no-k -o htest -v --exclude-tags=flaky,ipv6,squid"

if [ "$KONG_TEST_DATABASE" == "postgres" ]; then
    export TEST_CMD="bin/busted $BUSTED_ARGS,cassandra,off"
    psql -v ON_ERROR_STOP=1 -h ${KONG_TEST_PG_HOST} -U ${KONG_TEST_PG_USER} -d ${KONG_TEST_PG_DATABASE} <<-EOSQL
        CREATE user ${KONG_TEST_PG_USER}_ro;
        GRANT CONNECT ON DATABASE $KONG_TEST_PG_DATABASE TO ${KONG_TEST_PG_USER}_ro;
        \c $KONG_TEST_PG_DATABASE;
        GRANT USAGE ON SCHEMA public TO ${KONG_TEST_PG_USER}_ro;
        ALTER DEFAULT PRIVILEGES FOR ROLE $KONG_TEST_PG_USER IN SCHEMA public GRANT SELECT ON TABLES TO ${KONG_TEST_PG_USER}_ro;
EOSQL
elif [ "$KONG_TEST_DATABASE" == "cassandra" ]; then
    export KONG_TEST_CASSANDRA_KEYSPACE=kong_tests
    export KONG_TEST_DB_UPDATE_PROPAGATION=1
    export TEST_CMD="bin/busted $BUSTED_ARGS,postgres,off"
else
    export TEST_CMD="bin/busted $BUSTED_ARGS,postgres,cassandra,db"
fi

if [ "$TEST_SUITE" == "integration" ]; then
    if [[ "$TEST_SPLIT" == first* ]]; then
        # GitHub Actions, run first batch of integration tests
        eval "$TEST_CMD" $(ls -d spec/02-integration/* | head -n4)

    elif [[ "$TEST_SPLIT" == second* ]]; then
        # GitHub Actions, run second batch of integration tests
        # Note that the split here is chosen carefully to result
        # in a similar run time between the two batches, and should
        # be adjusted if imbalance become significant in the future
        eval "$TEST_CMD" $(ls -d spec/02-integration/* | tail -n+5)

    else
        # Non GitHub Actions
        eval "$TEST_CMD" spec/02-integration/
    fi
fi

if [ "$TEST_SUITE" == "dbless" ]; then
    eval "$TEST_CMD" spec/02-integration/02-cmd \
                     spec/02-integration/05-proxy \
                     spec/02-integration/04-admin_api/02-kong_routes_spec.lua \
                     spec/02-integration/04-admin_api/15-off_spec.lua
fi
if [ "$TEST_SUITE" == "plugins" ]; then
    set +ex
    rm -f .failed

    for p in spec/03-plugins/*; do
        echo
        cyan "--------------------------------------"
        cyan $(basename $p)
        cyan "--------------------------------------"
        echo

        $TEST_CMD $p || echo "* $p" >> .failed
    done

    cat kong-*.rockspec | grep kong- | grep -v zipkin | grep -v sidecar | grep "~" | grep -v kong-prometheus-plugin | while read line ; do
        REPOSITORY=`echo $line | sed "s/\"/ /g" | awk -F" " '{print $1}'`
        VERSION=`luarocks show $REPOSITORY | grep $REPOSITORY | head -1 | awk -F" " '{print $2}' | cut -f1 -d"-"`
        REPOSITORY=`echo $REPOSITORY | sed -e 's/kong-prometheus-plugin/kong-plugin-prometheus/g'`
        REPOSITORY=`echo $REPOSITORY | sed -e 's/kong-proxy-cache-plugin/kong-plugin-proxy-cache/g'`

        echo
        cyan "--------------------------------------"
        cyan $REPOSITORY $VERSION
        cyan "--------------------------------------"
        echo

        git clone https://github.com/Kong/$REPOSITORY.git --branch $VERSION --single-branch /tmp/test-$REPOSITORY || \
        git clone https://github.com/Kong/$REPOSITORY.git --branch v$VERSION --single-branch /tmp/test-$REPOSITORY
        sed -i 's/grpcbin:9000/localhost:15002/g' /tmp/test-$REPOSITORY/spec/*.lua
        sed -i 's/grpcbin:9001/localhost:15003/g' /tmp/test-$REPOSITORY/spec/*.lua
        cp -R /tmp/test-$REPOSITORY/spec/fixtures/* spec/fixtures/ || true
        pushd /tmp/test-$REPOSITORY
        luarocks make
        popd

        $TEST_CMD /tmp/test-$REPOSITORY/spec/ || echo "* $REPOSITORY" >> .failed

    done

    if [ -f .failed ]; then
        echo
        red "--------------------------------------"
        red "Plugin tests failed:"
        red "--------------------------------------"
        cat .failed
        exit 1
    else
        exit 0
    fi
fi
if [ "$TEST_SUITE" == "pdk" ]; then
    TEST_NGINX_RANDOMIZE=1 prove -I. -j$JOBS -r t/01-pdk
fi
if [ "$TEST_SUITE" == "unit" ]; then
    unset KONG_TEST_NGINX_USER KONG_PG_PASSWORD KONG_TEST_PG_PASSWORD
    scripts/autodoc
    bin/busted -v -o gtest spec/01-unit
    make lint
fi
