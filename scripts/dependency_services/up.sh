#!/usr/bin/env bash

if [ "${BASH_SOURCE-}" = "$0" ]; then
    echo "You must source this script: \$ source $0" >&2
    exit 33
fi

export KONG_SERVICE_ENV_FILE=$(mktemp)

if [ -n "$ZSH_VERSION" ]; then
    cwd=$(dirname $(readlink -f ${(%):-%N}))
else
    cwd=$(dirname $(readlink -f ${BASH_SOURCE[0]}))
fi

/usr/bin/env bash "$cwd/common.sh" $KONG_SERVICE_ENV_FILE up
if [ $? -ne 0 ]; then
    echo "Something goes wrong, please check common.sh output"
    exit 1
fi

. $KONG_SERVICE_ENV_FILE

stop_services () {
    if test -n "$COMPOSE_FILE" && test -n "$COMPOSE_PROJECT_NAME"; then
        bash "$cwd/common.sh" $KONG_SERVICE_ENV_FILE down
    fi

    for i in $(cat $KONG_SERVICE_ENV_FILE | cut -f2 | cut -d '=' -f1); do
      unset $i
    done

    rm -rf $KONG_SERVICE_ENV_FILE
    unset KONG_SERVICE_ENV_FILE

    unset -f stop_services
}

echo 'Services are up! Use "stop_services" to stop services and cleanup environment variables,
or use "deactivate" to cleanup the venv.'
