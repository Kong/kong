#!/usr/bin/env bash
set -ex

function cyan() {
    echo -e "\033[1;36m$*\033[0m"
}
function red() {
    echo -e "\033[1;31m$*\033[0m"
}
function retry() {
    local result=0
    local count=1
    while [ $count -le 3 ]; do
        [ $result -ne 0 ] && {
            echo -e "\n\033[33;1mThe command \"$@\" failed. Retrying, $count of 3.\033[0m\n" >&2
        }
        "$@"
        result=$?
        [ $result -eq 0 ] && break
        count=$(($count + 1))
        sleep 1
    done

    [ $count -eq 3 ] && {
        echo "\n\033[33;1mThe command \"$@\" failed 3 times.\033[0m\n" >&2
    }

    return $result
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
        retry "$TEST_CMD $(ls -d spec/02-integration/* | head -n4)"

    elif [[ "$TEST_SPLIT" == second* ]]; then
        # GitHub Actions, run second batch of integration tests
        # Note that the split here is chosen carefully to result
        # in a similar run time between the two batches, and should
        # be adjusted if imbalance become significant in the future
        retry "$TEST_CMD $(ls -d spec/02-integration/* | tail -n+5)"

    else
        # Non GitHub Actions
        retry "$TEST_CMD spec/02-integration/*"
    fi
fi

if [ "$TEST_SUITE" == "dbless" ]; then
    retry "$TEST_CMD spec/02-integration/02-cmd/*"
    retry "$TEST_CMD spec/02-integration/05-proxy/*"
    retry "$TEST_CMD spec/02-integration/04-admin_api/02-kong_routes_spec.lua"
    retry "$TEST_CMD spec/02-integration/04-admin_api/15-off_spec.lua"
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

        retry "$TEST_CMD $p" || echo "* $p" >> .failed
    done

    cat kong-*.rockspec | grep kong- | grep -v zipkin | grep -v sidecar | grep "~" | while read line ; do
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
        cp -R /tmp/test-$REPOSITORY/spec/fixtures/* spec/fixtures/ || true
        pushd /tmp/test-$REPOSITORY
        retry "luarocks make"
        popd

        retry "$TEST_CMD /tmp/test-$REPOSITORY/spec/" || echo "* $REPOSITORY" >> .failed

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
    scripts/autodoc-admin-api
    bin/busted -v -o gtest spec/01-unit
    make lint
fi
