#!/usr/bin/env bash

set -e

if [[ $ENABLE_COREDUMP_DEBUG = true ]]; then
    ulimit -c unlimited
    mkdir -p /tmp/cores
    chmod 777 /tmp/cores
    echo '/tmp/cores/core.%e.%p' | sudo tee /proc/sys/kernel/core_pattern
    sudo sysctl -w fs.suid_dumpable=2
    sudo sysctl -p
fi

function cyan() {
    echo -e "\033[1;36m$*\033[0m"
}

function red() {
    echo -e "\033[1;31m$*\033[0m"
}

function yellow() {
    echo -e "\033[1;33m$*\033[0m"
}

# Returns the fully qualified path to the top-level kong-ee directory
__repo_root_path() {
  local path
  path=$(cd $(dirname ${BASH_SOURCE[0]})/../ && pwd)
  echo "$path"
}

create_postgresql_user() {
  psql -v ON_ERROR_STOP=1 -h localhost --username "$KONG_TEST_PG_USER" <<-EOSQL
        CREATE user ${KONG_TEST_PG_USER}_ro;
        GRANT CONNECT ON DATABASE $KONG_TEST_PG_DATABASE TO ${KONG_TEST_PG_USER}_ro;
        \c $KONG_TEST_PG_DATABASE;
        GRANT USAGE ON SCHEMA public TO ${KONG_TEST_PG_USER}_ro;
        ALTER DEFAULT PRIVILEGES FOR ROLE $KONG_TEST_PG_USER IN SCHEMA public GRANT SELECT ON TABLES TO ${KONG_TEST_PG_USER}_ro;
EOSQL
}

if [[ ! $KONG_LICENSE_DATA == *"signature"* || ! $KONG_LICENSE_DATA == *"payload"* ]]; then
  # the check above is a bit lame, but the best we can do without requiring
  # yet more additional dependenies like jq or similar.
  yellow "KONG_LICENSE_DATA is not set on invalid. Please use Kong/kong-license action to download."
  exit 1
fi
export KONG_TEST_LICENSE_DATA=$KONG_LICENSE_DATA


export BUSTED_ARGS=${BUSTED_ARGS:-"-o hjtest -Xoutput $XML_OUTPUT/report.xml -v --exclude-tags=flaky,ipv6,ce"}
spec_ee_lua_path="$(__repo_root_path)/spec-ee/fixtures/custom_plugins/?.lua;$(__repo_root_path)/spec-ee/fixtures/custom_plugins/?/init.lua"
export LUA_PATH="$LUA_PATH;$spec_ee_lua_path"

if [ "$KONG_TEST_DATABASE" == "postgres" ]; then
    export TEST_CMD="bin/busted $BUSTED_ARGS,off"
    create_postgresql_user

elif [ "$KONG_TEST_DATABASE" == "cassandra" ]; then
    echo "Cassandra is no longer supported"
    exit 1
else
    export TEST_CMD="bin/busted $BUSTED_ARGS,postgres,db"
fi


### DEBUG: print memory usage to adjust self-runner VM memory
watch -n 30 -t -w bash -c "free -m > /tmp/memusage.txt" 2>&1 >/dev/null &
function print_memusage {
    cat /tmp/memusage.txt || true
    killall watch || true
}
trap print_memusage EXIT


if [ "$TEST_SUITE" == "aws-integration" ]; then
    eval "$TEST_CMD" spec-ee/thirdparty-integration/aws
fi


if [ "$TEST_SUITE" == "plugins-ee" ]; then
    scripts/enterprise_plugin.sh build-deps
    rm -f .failed

    # TODO: add the ai-azure-content-safety plugin here?
    declare -A plugins_to_test=(
        ["first"]="openid-connect"
        ["second"]="ldap-auth-advanced"
        ["third"]="kafka-log oas-validation saml vault-auth"
        ["fourth"]="upstream-oauth mtls-auth header-cert-auth request-validator kafka-upstream konnect-application-auth opa"
        ["fips-first"]="openid-connect"
        ["fips-second"]="mtls-auth saml header-cert-auth"
    )

    plugins=${plugins_to_test["$TEST_SPLIT"]}

    if [[ -z $plugins ]]; then
        red "No plugins to test for split: $TEST_SPLIT"
        exit 1
    fi

    for plugin in $plugins; do
        echo
        cyan "--------------------------------------"
        cyan Test plugin: $plugin
        cyan "--------------------------------------"
        echo

        scripts/enterprise_plugin.sh test $plugin || echo "* $plugin" >> .failed
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
