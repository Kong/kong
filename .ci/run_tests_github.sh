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


KONG_LICENSE_URL="https://download.konghq.com/internal/kong-gateway/license.json"
KONG_LICENSE_DATA=$(curl \
  --silent \
  --location \
  --retry 3 \
  --retry-delay 3 \
  --user "$PULP_USERNAME:$PULP_PASSWORD" \
  --url "$KONG_LICENSE_URL"
)
export KONG_LICENSE_DATA
if [[ ! $KONG_LICENSE_DATA == *"signature"* || ! $KONG_LICENSE_DATA == *"payload"* ]]; then
  # the check above is a bit lame, but the best we can do without requiring
  # yet more additional dependenies like jq or similar.
  yellow "failed to download the Kong Enterprise license file!
    $KONG_LICENSE_DATA"
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

if [[ "$KONG_TEST_COVERAGE" = true ]]; then
    export TEST_CMD="$TEST_CMD --keep-going"
fi

if [ "$TEST_SUITE" == "integration" ]; then
    if [[ "$TEST_SPLIT" == first-CE ]]; then
        # GitHub Actions, run first batch of integration tests
        eval "$TEST_CMD" $(ls -d spec/02-integration/* | grep -v 05-proxy)

    elif [[ "$TEST_SPLIT" == second-CE ]]; then
        # GitHub Actions, run second batch of integration tests
        # Note that the split here is chosen carefully to result
        # in a similar run time between the two batches, and should
        # be adjusted if imbalance become significant in the future
        eval "$TEST_CMD" $(ls -d spec/02-integration/* | grep 05-proxy)

    elif [[ "$TEST_SPLIT" == first-EE ]]; then
        pushd .ci/ad-server && make build-ad-server && popd
        eval "$TEST_CMD" $(ls -d spec-ee/02-integration/* | head -n4)

    elif [[ "$TEST_SPLIT" == second-EE ]]; then
        pushd .ci/ad-server && make build-ad-server && popd
        eval "$TEST_CMD" $(ls -d spec-ee/02-integration/* | sed -n '5p')

    elif [[ "$TEST_SPLIT" == third-EE ]]; then
        pushd .ci/ad-server && make build-ad-server && popd
        eval "$TEST_CMD" $(ls -d spec-ee/02-integration/* | tail -n+6)

    else
        # Non GitHub Actions
        eval "$TEST_CMD" spec/02-integration/ spec-ee/02-integration
    fi
fi

if [ "$TEST_SUITE" == "dbless" ]; then
    eval "$TEST_CMD" spec/02-integration/02-cmd \
                     spec/02-integration/05-proxy \
                     spec/02-integration/04-admin_api/02-kong_routes_spec.lua \
                     spec/02-integration/04-admin_api/15-off_spec.lua \
                     spec/02-integration/08-status_api/03-readiness_endpoint_spec.lua \
                     spec/02-integration/08-status_api/01-core_routes_spec.lua \
                     spec/02-integration/11-dbless \
                     spec/02-integration/20-wasm

fi

if [ "$TEST_SPLIT" == "first-fips" ]; then
    # we test 05-fips first as a sanity check
    eval "$TEST_CMD" \
                     spec-ee/05-fips \
                     spec/03-plugins/16-jwt spec/03-plugins/19-hmac-auth \
                     spec/03-plugins/20-ldap-auth spec/03-plugins/25-oauth2 \
                     spec/03-plugins/29-acme \
                     spec/01-unit \
                     spec-ee/01-unit \
                     spec-ee/03-plugins/01-prometheus spec-ee/03-plugins/10-key-auth \
                     spec-ee/03-plugins/11-basic-auth spec-ee/03-plugins/01-plugins_order_spec.lua \
                     spec-ee/03-plugins/02-websocket-log-plugins_spec.lua \
                     spec-ee/02-integration/00-kong  spec-ee/02-integration/01-rbac \
                     spec-ee/02-integration/02-workspaces spec-ee/02-integration/04-dev-portal
fi

if [ "$TEST_SPLIT" == "second-fips" ]; then
    pushd .ci/ad-server && make build-ad-server && popd
    eval "$TEST_CMD" spec-ee/02-integration/03-vitals \
                     spec-ee/02-integration/05-admin-gui spec-ee/02-integration/06-rate-limiting-library \
                     spec-ee/02-integration/07-audit-log spec-ee/02-integration/08-new-dao \
                     spec-ee/02-integration/09-tracing spec-ee/02-integration/10-groups \
                     spec-ee/02-integration/11-cmd spec-ee/02-integration/12-counters \
                     spec-ee/02-integration/13-event_hooks spec-ee/02-integration/14-hybrid_mode \
                     spec-ee/02-integration/15-consumer-groups spec-ee/02-integration/16-plugins-ordering \
                     spec-ee/02-integration/17-keyring spec-ee/02-integration/18-websockets \
                     spec-ee/02-integration/19-vaults spec-ee/02-integration/20-dp-resilience \
                     spec-ee/02-integration/21-profiling spec-ee/02-integration/22-analytics \
                     spec-ee/02-integration/22-plugins-iterator
fi

if [ "$TEST_SUITE" == "aws-integration" ]; then
    eval "$TEST_CMD" spec-ee/thirdparty-integration/aws
fi

if [ "$TEST_SUITE" == "plugins" ]; then
    set +ex
    rm -f .failed
    PLUGINS=""

    if [[ "$TEST_SPLIT" == first-CE ]]; then
        # GitHub Actions, run first batch of plugin tests
        PLUGINS=$(ls -d spec/03-plugins/* | head -n22)

    elif [[ "$TEST_SPLIT" == second-CE ]]; then
        # GitHub Actions, run second batch of plugin tests
        # Note that the split here is chosen carefully to result
        # in a similar run time between the two batches, and should
        # be adjusted if imbalance become significant in the future
        PLUGINS=$(ls -d spec/03-plugins/* | tail -n+23)

    elif [[ "$TEST_SPLIT" == first-EE ]]; then
        PLUGINS=$(ls -d spec-ee/03-plugins/*)

    else
        # Non GitHub Actions
        PLUGINS=$(ls -d spec/03-plugins/* spec-ee/03-plugins/*)
    fi

    for p in $PLUGINS; do
        echo
        cyan "--------------------------------------"
        cyan $(basename $p)
        cyan "--------------------------------------"
        echo

        $TEST_CMD $p || echo "* $p" >> .failed
        mv $XML_OUTPUT/report.xml $XML_OUTPUT/report-$RANDOM.xml
    done

    if [[ "$TEST_SPLIT" == second* ]] || [[ "$TEST_SPLIT" != first* ]] || [[ "$TEST_SPLIT" != third* ]]; then
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
    fi

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
    prove -I. -r t
fi

if [ "$TEST_SUITE" == "plugins-ee" ]; then
    scripts/enterprise_plugin.sh build-deps
    rm -f .failed

    declare -A plugins_to_test=(
        ["first"]="forward-proxy application-registration canary jwe-decrypt websocket-size-limit"
        ["second"]="mocking proxy-cache-advanced upstream-timeout app-dynamics"
        ["third"]="jwt-signer kafka-upstream kafka-log statsd-advanced graphql-proxy-cache-advanced websocket-validator"
        ["fourth"]="openid-connect jq tls-metadata-headers"
        ["fifth"]="mtls-auth request-validator tls-handshake-modifier route-by-header"
        ["sixth"]="key-auth-enc request-transformer-advanced saml graphql-rate-limiting-advanced"
        ["seventh"]="rate-limiting-advanced exit-transformer route-transformer-advanced vault-auth"
        ["eighth"]="response-transformer-advanced oas-validation opa konnect-application-auth oauth2-introspection degraphql"
        ["ninth"]="ldap-auth-advanced"
        ["fips-first"]="jwe-decrypt jwt-signer openid-connect saml"
        ["fips-second"]="mtls-auth"
        ["fips-third"]="key-auth-enc oauth2-introspection"
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
