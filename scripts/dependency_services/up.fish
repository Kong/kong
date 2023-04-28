#!/usr/bin/env fish

set cwd (dirname (status --current-filename))

set -xg KONG_SERVICE_ENV_FILE $(mktemp)

bash "$cwd/common.sh" $KONG_SERVICE_ENV_FILE

if test $status -ne 0
    echo "Something goes wrong, please check common.sh output"
    return
end

source $KONG_SERVICE_ENV_FILE

function stop_services -d 'Stop dependency services of Kong and clean up environment variables.'
    if test -n $COMPOSE_FILE && test -n $COMPOSE_PROJECT_NAME
        docker compose down
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
