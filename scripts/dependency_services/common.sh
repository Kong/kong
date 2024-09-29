#!/usr/bin/env bash

if [ "$#" -lt 2 ]; then
    echo "Usage: $0 KONG_SERVICE_ENV_FILE <extra_plugins_ee_directory>"
    exit 1
fi

if [ -d "$3/.pongo" ]; then
    plugins_ee_directory=$3
elif [ ! -z "$3" ]; then
    echo "Requested to start extra plugins-ee services at $3, but it doesn't contain a .pongo directory"
fi

cwd=$(realpath $(dirname $(readlink -f "${BASH_SOURCE[0]}")))
PATH=$PATH:$cwd

if [ ! -z "$plugins_ee_directory" ] && ! yq --version >/dev/null 2>&1; then
    binary_name=""
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        binary_name="yq_linux"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        binary_name="yq_darwin"
    else
        echo "Unsupported OS for yq: $OSTYPE"
        exit 1
    fi
    if [[ $(uname -m) == "x86_64" ]]; then
        binary_name="${binary_name}_amd64"
    else
        binary_name="${binary_name}_arm64"
    fi
    wget "https://github.com/mikefarah/yq/releases/download/v4.40.5/${binary_name}" -qO "$cwd/yq"
    chmod +x "$cwd/yq"
fi

if docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE="docker compose"
elif [ -z "$(which docker-compose)" ]; then
    echo "docker-compose or docker compose plugin not installed"
    exit 1
else
    DOCKER_COMPOSE="docker-compose"
fi

if [ "$2" == "down" ]; then
  NETWORK_NAME="default" $DOCKER_COMPOSE down -v --remove-orphans
  exit 0
fi

KONG_SERVICE_ENV_FILE=$1
# clear the file
> "$KONG_SERVICE_ENV_FILE"

# Initialize parallel arrays for service names and port definitions
services=()
port_defs=()

ptemp=$cwd/.pongo-compat

compose_file=$cwd/docker-compose-test-services.yml

if [ ! -z "$plugins_ee_directory" ]; then
    echo "Starting extra plugins-ee services at $plugins_ee_directory"
    rm -rf "$ptemp"
    mkdir -p "$ptemp"

    pushd "$plugins_ee_directory/.pongo" >/dev/null

    shopt -s nullglob
    yaml_files=(*.yml *.yaml)
    shopt -u nullglob

    for f in "${yaml_files[@]}"; do
        compose_file="$compose_file:$(pwd)/$f"
        for service in $(yq '.services | keys| .[]' <"$f"); do
            # rest-proxy -> rest_proxy
            services+=( "$service" )
            service_normalized="${service//-/_}"
            ports=""
            for port in $(yq ".services.$service.ports.[]" <"$f" | rev | cut -d: -f1 | rev); do
                # KEYCLOAK_PORT_8080:8080
                ports="$ports ${service_normalized}_PORT_${port}:${port}"
            done
            port_defs+=( "$ports" )
        done
    done
    popd >/dev/null

    ln -sf "$(pwd)/$plugins_ee_directory/.pongo" "$ptemp/.pongo"
    ln -sf "$(pwd)/$plugins_ee_directory/spec" "$ptemp/spec"
    export PONGO_WD=$(realpath "$plugins_ee_directory")
    pushd "$ptemp" >/dev/null
fi

export COMPOSE_FILE="$compose_file"
export COMPOSE_PROJECT_NAME="$(basename $(realpath $cwd/../../))-$(basename ${KONG_VENV:-kong-dev})"
echo "export COMPOSE_FILE=$COMPOSE_FILE" >> "$KONG_SERVICE_ENV_FILE"
echo "export COMPOSE_PROJECT_NAME=$COMPOSE_PROJECT_NAME" >> "$KONG_SERVICE_ENV_FILE"

NETWORK_NAME="default" $DOCKER_COMPOSE up -d --build --wait --remove-orphans

if [ ! -z "$plugins_ee_directory" ]; then
    unset PONGO_WD
    popd >/dev/null
fi

if [ $? -ne 0 ]; then
    echo "Something goes wrong, please check $DOCKER_COMPOSE output"
    exit 1
fi

# Add elements to the parallel arrays
services+=("postgres")
port_defs+=("PG_PORT:5432")

services+=("redis")
port_defs+=("REDIS_PORT:6379 REDIS_SSL_PORT:6380")

services+=("redis-stack")
port_defs+=("REDIS_STACK_PORT:6379")

services+=("grpcbin")
port_defs+=("GRPCBIN_PORT:9000 GRPCBIN_SSL_PORT:9001")

services+=("zipkin")
port_defs+=("ZIPKIN_PORT:9411")

_kong_added_envs=""

# Not all env variables need all three prefixes, but we add all of them for simplicity
env_prefixes="KONG_ KONG_TEST_ KONG_SPEC_TEST_"

for ((i = 0; i < ${#services[@]}; i++)); do
    svc="${services[i]}"

    for port_def in ${port_defs[i]}; do
        env_name=$(echo "$port_def" | cut -d: -f1)
        private_port=$(echo "$port_def" | cut -d: -f2)
        exposed_port="$($DOCKER_COMPOSE port "$svc" "$private_port" | cut -d: -f2)"

        if [ -z "$exposed_port" ]; then
            echo "Port $env_name for service $svc unknown"
            continue
        fi

        for prefix in $env_prefixes; do
            _kong_added_envs="$_kong_added_envs ${prefix}${env_name}"
            echo "export ${prefix}${env_name}=$exposed_port" >> "$KONG_SERVICE_ENV_FILE"
        done
    done

    # all services go to localhost
    for prefix in $env_prefixes; do
        svcn="${svc//-/_}"
        echo "export ${prefix}$(echo "$svcn" | tr '[:lower:]' '[:upper:]')_HOST=127.0.0.1" >> "$KONG_SERVICE_ENV_FILE"
    done
done
