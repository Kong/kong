#!/bin/bash

export KONG_ENV_FILE=$(mktemp) || exit 1
export KONG_ENV_DOWN_FILE=$(mktemp) || exit 1

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


bash "$cwd/common.sh" $KONG_ENV_FILE $KONG_ENV_DOWN_FILE
if [ $? -ne 0 ]; then
    echo "Something goes wrong, please check common.sh output"
    return
fi

source $KONG_ENV_FILE

stop_services () {
    for i in $(cat $KONG_ENV_DOWN_FILE); do
      unset $i
    done

    rm -rf $KONG_ENV_FILE $KONG_ENV_DOWN_FILE
    unset KONG_ENV_FILE KONG_ENV_DOWN_FILE

    if test -n "$docker_compose_file" && test -n "$docker_compose_project"; then
        docker-compose -f "$docker_compose_file" -p "$docker_compose_project" down
        unset docker_compose_file docker_compose_project cwd
    fi
    unset -f stop_services
}

echo 'Services are up! Use "stop_services" to stop services and cleanup environment variables,
or use "deactivate" to cleanup the venv.'
