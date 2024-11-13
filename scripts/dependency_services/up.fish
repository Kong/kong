#!/usr/bin/env fish

set cwd (dirname (status --current-filename))

set -xg KONG_SERVICE_ENV_FILE $(mktemp)

bash "$cwd/common.sh" $KONG_SERVICE_ENV_FILE up

if test $status -ne 0
    echo "Something goes wrong, please check common.sh output"
    exit 1
end

source $KONG_SERVICE_ENV_FILE

function stop_services -d 'Stop dependency services of Kong and clean up environment variables.'
    # set this again in child process without need to export env var
    set cwd (dirname (status --current-filename))

    if test -n $COMPOSE_FILE && test -n $COMPOSE_PROJECT_NAME
        bash "$cwd/common.sh" $KONG_SERVICE_ENV_FILE down
    end

    for i in (cat $KONG_SERVICE_ENV_FILE | cut -d ' ' -f2 | cut -d '=' -f1)
      set -e $i
    end

    rm -f $KONG_SERVICE_ENV_FILE
    set -e KONG_SERVICE_ENV_FILE

    functions -e stop_services
end

echo 'Services are up! Use "stop_services" to stop services and cleanup environment variables,
or use "deactivate" to cleanup the venv.'
