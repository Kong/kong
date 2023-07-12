#!/usr/bin/env bash

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 KONG_SERVICE_ENV_FILE [up|down]"
    exit 1
fi

if docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE="docker compose"
elif [[ -z $(which docker-compose) ]]; then
    echo "docker-compose or docker compose plugin not installed"
    exit 1
else
    DOCKER_COMPOSE="docker-compose"
fi

if [ "$2" == "down" ]; then
  $DOCKER_COMPOSE down -v
  exit 0
fi

KONG_SERVICE_ENV_FILE=$1
# clear the file
> $KONG_SERVICE_ENV_FILE

cwd=$(realpath $(dirname $(readlink -f ${BASH_SOURCE[0]})))

export COMPOSE_FILE=$cwd/docker-compose-test-services.yml
export COMPOSE_PROJECT_NAME="$(basename $(realpath $cwd/../../))-$(basename ${KONG_VENV:-kong-dev})"
echo "export COMPOSE_FILE=$COMPOSE_FILE" >> $KONG_SERVICE_ENV_FILE
echo "export COMPOSE_PROJECT_NAME=$COMPOSE_PROJECT_NAME" >> $KONG_SERVICE_ENV_FILE

$DOCKER_COMPOSE up -d

if [ $? -ne 0 ]; then
    echo "Something goes wrong, please check $DOCKER_COMPOSE output"
    exit 1
fi

# [service_name_in_docker_compose]="env_var_name_1:port_1_in_docker_compose env_var_name_2:port_2_in_docker_compose"
declare -A ports=(
    ["postgres"]="PG_PORT:5432"
    ["redis"]="REDIS_PORT:6379 REDIS_SSL_PORT:6380"
    ["grpcbin"]="GRPCBIN_PORT:9000 GRPCBIN_SSL_PORT:9001"
    ["zipkin"]="ZIPKIN_PORT:9411"
    # ["opentelemetry"]="OTELCOL_HTTP_PORT:4318 OTELCOL_ZPAGES_PORT:55679"
)

_kong_added_envs=""

# not all env variable needs all three prefix in all times, but we add all of them
# for simplicity: there's no side effect after all
env_prefixes="KONG_ KONG_TEST_ KONG_SPEC_TEST_"

for svc in "${!ports[@]}"; do
    for port_def in ${ports[$svc]}; do
        env_name=$(echo $port_def |cut -d: -f1)
        private_port=$(echo $port_def |cut -d: -f2)
        exposed_port=$($DOCKER_COMPOSE port $svc $private_port | cut -d: -f2)
        if [ -z $exposed_port ]; then
            echo "Port $env_name for service $svc unknown"
            continue
        fi
        for prefix in $env_prefixes; do
            _kong_added_envs="$_kong_added_envs ${prefix}${env_name}"
            echo "export ${prefix}${env_name}=$exposed_port" >> $KONG_SERVICE_ENV_FILE
        done
    done
done
