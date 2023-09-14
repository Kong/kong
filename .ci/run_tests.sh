#!/usr/bin/env bash
set -e

function cyan() {
    echo -e "\033[1;36m$*\033[0m"
}
function red() {
    echo -e "\033[1;31m$*\033[0m"
}

export BUSTED_ARGS="--no-k -o htest --repeat 200 -v --exclude-tags=flaky,ipv6"

if [ "$KONG_TEST_DATABASE" == "postgres" ]; then
    export TEST_CMD="bin/busted $BUSTED_ARGS,off"

    psql -v ON_ERROR_STOP=1 -h localhost --username "$KONG_TEST_PG_USER" <<-EOSQL
        CREATE user ${KONG_TEST_PG_USER}_ro;
        GRANT CONNECT ON DATABASE $KONG_TEST_PG_DATABASE TO ${KONG_TEST_PG_USER}_ro;
        \c $KONG_TEST_PG_DATABASE;
        GRANT USAGE ON SCHEMA public TO ${KONG_TEST_PG_USER}_ro;
        ALTER DEFAULT PRIVILEGES FOR ROLE $KONG_TEST_PG_USER IN SCHEMA public GRANT SELECT ON TABLES TO ${KONG_TEST_PG_USER}_ro;
EOSQL

elif [ "$KONG_TEST_DATABASE" == "cassandra" ]; then
  echo "Cassandra is no longer supported"
  exit 1

else
    export TEST_CMD="bin/busted $BUSTED_ARGS,postgres,db"
fi



if [ "$TEST_SUITE" == "integration" ]; then

        eval "$TEST_CMD" spec/02-integration/06-invalidations/02-core_entities_invalidations_spec.lua

fi

