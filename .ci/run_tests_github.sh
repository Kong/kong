#!/usr/bin/env bash

set -e

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

# Returns the KONG_DISTRIBUTION_VERSION value of the current branch
kong_distribution_version() {
  # Determine the version of kong-distributions required (build.yml)
  grep "^\s*KONG_DISTRIBUTIONS_VERSION=" $(__repo_root_path)/.requirements | head -1 | sed -e 's/.*=//' | tr -d '\n'
}

# Installs a plugin into spec-ee/fixtures/custom_plugins/kong/plugins
# Arguments:
#   plugin repo name
# Example Usage:
#   install_custom_plugin kong-plugin-enterprise-proxy-cache
install_custom_plugin() {
  local plugin_repo_name=${1?plugin_repo_name argument required}
  local tmpdir
  local plugin_version
  export plugin_repo_name

  tmpdir=$(dirname $(mktemp -u))
  git clone https://$GITHUB_TOKEN:@github.com/Kong/kong-distributions \
    $tmpdir/kong-distributions -b $(kong_distribution_version) --depth 1

  plugin_version=$(yq e '.enterprise[] | select(.repo_name==env(plugin_repo_name)) | .version' \
    $tmpdir/kong-distributions/kong-images/build.yml)

  if [[ -z "$plugin_version" ]]; then
    echo "Unable to determine plugin version. Is $plugin_repo_name in build.yml?"
    exit 1
  fi

  git clone https://$GITHUB_TOKEN:@github.com/Kong/$plugin_repo_name.git \
    $tmpdir/$plugin_repo_name -b $plugin_version --depth 1

  cp -r $tmpdir/$plugin_repo_name/kong/plugins/* \
    $(__repo_root_path)/spec-ee/fixtures/custom_plugins/kong/plugins/

  rm -rf ${tmpdir}/kong-distributions ${tmpdir}/$plugin_repo_name
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


export BUSTED_ARGS=${BUSTED_ARGS:-"-o htest -v --exclude-tags=flaky,ipv6,squid,ce"}
spec_ee_lua_path="$(__repo_root_path)/spec-ee/fixtures/custom_plugins/?.lua;$(__repo_root_path)/spec-ee/fixtures/custom_plugins/?/init.lua"
export LUA_PATH="$LUA_PATH;$spec_ee_lua_path"

if [ "$KONG_TEST_DATABASE" == "postgres" ]; then
    export TEST_CMD="bin/busted $BUSTED_ARGS,cassandra,off"
    create_postgresql_user

elif [ "$KONG_TEST_DATABASE" == "cassandra" ]; then
    export KONG_TEST_CASSANDRA_KEYSPACE=kong_tests
    export KONG_TEST_DB_UPDATE_PROPAGATION=1
    export TEST_CMD="bin/busted $BUSTED_ARGS,postgres,off"

else
    export TEST_CMD="bin/busted $BUSTED_ARGS,postgres,cassandra,db"
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
                     spec/02-integration/04-admin_api/15-off_spec.lua
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
    prove -I. -r t/01-pdk
fi

if [ "$TEST_SUITE" == "plugins-ee" ]; then
    if [[ "$TEST_SPLIT" == first ]]; then
        make test-build-pongo-deps
        make test-forward-proxy || echo "* forward-proxy" >> .failed
        make test-application-registration || echo "* application-registration" >> .failed
        make test-graphql-proxy-cache-advanced || echo "* graphql-proxy-cache-advanced" >> .failed
        make test-graphql-rate-limiting-advanced || echo "* graphql-rate-limiting-advanced" >> .failed
        make test-jq || echo "* jq" >> .failed
        make test-response-transformer-advanced || echo "* response-transformer-advanced" >> .failed

    elif [[ "$TEST_SPLIT" == second ]]; then
        make test-build-pongo-deps
        make test-oauth2-introspection || echo "* oauth2-introspectio" >> .failed
        make test-proxy-cache-advanced || echo "* proxy-cache-advanced" >> .failed

    elif [[ "$TEST_SPLIT" == third ]]; then
        make test-build-pongo-deps
        make test-mocking || echo "* mocking" >> .failed
        make test-tls-handshake-modifier || echo "* tls-handshake-modifier" >> .failed
        make test-upstream-timeout || echo "* upstream-timeout" >> .failed
        make test-key-auth-enc || echo "* key-auth-enc" >> .failed
        make test-websocket-size-limit || echo "* websocket-size-limit" >> .failed
        make test-rate-limiting-advanced || echo "* rate-limiting-advanced" >> .failed


    elif [[ "$TEST_SPLIT" == fourth ]]; then
        make test-build-pongo-deps
        make test-kafka-upstream || echo "* kafka-upstream" >> .failed
        make test-kafka-log || echo "* kafka-log" >> .failed
        make test-route-by-header || echo "* route-by-header" >> .failed
        make test-statsd-advanced || echo "* statsd-advanced" >> .failed
        make test-websocket-validator || echo "* websocket-validator" >> .failed
        make test-jwt-signer || echo "* jwt-signer" >> .failed
        make test-vault-auth || echo "* vault-auth" >> .failed

    elif [[ "$TEST_SPLIT" == fifth ]]; then
        make test-build-pongo-deps
        make test-openid-connect || echo "* openid-connect" >> .failed
        make test-route-transformer-advanced || echo "* route-transformer-advanced" >> .failed
        make test-exit-transformer || echo "* exit-transformer" >> .failed
        make test-request-transformer-advanced || echo "* request-transformer-advanced" >> .failed
        make test-tls-metadata-headers || echo "* tls-metadata-headers" >> .failed
        make test-konnect-application-auth || echo "* konnect-application-auth" >> .failed

    elif [[ "$TEST_SPLIT" == sixth ]]; then
        make test-build-pongo-deps
        make test-ldap-auth-advanced || echo "* ldap-auth-advanced" >> .failed
        make test-degraphql || echo "* degraphql" >> .failed
        make test-canary || echo "* canary" >> .failed
        make test-opa || echo "* opa" >> .failed
        make test-datadog-tracing || echo "* datadog-tracing" >> .failed

    elif [[ "$TEST_SPLIT" == seventh ]]; then
        make test-saml || echo "* saml" >> .failed
        make test-request-validator || echo "* test-request-validator" >> .failed
        make test-mtls-auth || echo "* mtls-auth" >> .failed
        make test-oas-validation || echo "* oas-validation" >> .failed
        make test-app-dynamics || echo "* app-dynamics" >> .failed
        make test-jwe-decrypt || echo "* jwe-decrypt" >> .failed
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
