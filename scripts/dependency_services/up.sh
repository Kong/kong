#!/bin/bash

if [ "${BASH_SOURCE-}" = "$0" ]; then
    echo "You must source this script: \$ source $0" >&2
    exit 33
fi

cwd=$(realpath $(dirname $(readlink -f $BASH_SOURCE[0])))
docker_compose_file=${cwd}/docker-compose-test-services.yml
docker_compose_project=kong

docker-compose -f "$docker_compose_file" -p "$docker_compose_project" up -d

if [ $? -ne 0 ]; then
    echo "Something goes wrong, please check docker-compose output"
    return
fi

# [service_name_in_docker_compose]="env_var_name_1:port_1_in_docker_compose env_var_name_2:port_2_in_docker_compose"
declare -A ports=(
    ["postgres"]="PG_PORT:5432"
    ["cassandra"]="CASSANDRA_PORT:9042"
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
        exposed_port=$(docker-compose -f "$docker_compose_file" -p "$docker_compose_project" port $svc $private_port | cut -d: -f2)
        if [ -z $exposed_port ]; then
            echo "Port $env_name for service $svc unknown"
            continue
        fi
        for prefix in $env_prefixes; do
            _kong_added_envs="$_kong_added_envs ${prefix}${env_name}"
            eval "export ${prefix}${env_name}=$exposed_port"
        done
    done
done

export _kong_added_envs

stop_services () {
    for v in $_kong_added_envs; do
        eval "unset $v"
    done

    unset _kong_added_envs
    if test -n "$docker_compose_file" && test -n "$docker_compose_project"; then
        docker-compose -f "$docker_compose_file" -p "$docker_compose_project" down
        unset docker_compose_file docker_compose_project cwd
    fi
    unset -f stop_services
}

echo 'Services are up! Use "stop_services" to stop services and cleanup environment variables,
or use "deactivate" to cleanup the venv.'