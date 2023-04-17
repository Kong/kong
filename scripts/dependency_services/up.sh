#!/bin/bash

KONG_ENV_FILE=.env
KONG_ENV_DOWN_FILE=.env.down

if [ "${BASH_SOURCE-}" = "$0" ]; then
    echo "You must source this script: \$ source $0" >&2
    exit 33
fi

if [ -n "$ZSH_VERSION" ]; then
    cwd=$(realpath $(dirname $(readlink -f ${(%):-%N})))
else
    cwd=$(realpath $(dirname $(readlink -f $BASH_SOURCE[0])))
fi

docker_compose_file=${cwd}/docker-compose-test-services.yml
docker_compose_project=kong


bash "$cwd/common.sh"
if [ $? -ne 0 ]; then
    echo "Something goes wrong, please check common.sh output"
    return
fi

source $KONG_ENV_FILE

stop_services () {
    unset $(cat $KONG_ENV_DOWN_FILE | xargs -d '\n')

    if test -n "$docker_compose_file" && test -n "$docker_compose_project"; then
        docker-compose -f "$docker_compose_file" -p "$docker_compose_project" down
        unset docker_compose_file docker_compose_project cwd
    fi
    unset -f stop_services
}

echo 'Services are up! Use "stop_services" to stop services and cleanup environment variables,
or use "deactivate" to cleanup the venv.'