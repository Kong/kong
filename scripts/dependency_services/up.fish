#!/usr/bin/env fish

set cwd (dirname (status --current-filename))

set -xg docker_compose_file $cwd/docker-compose-test-services.yml
set -xg docker_compose_project kong

set -xg KONG_ENV_FILE $(mktemp) || exit 1
set -xg KONG_ENV_DOWN_FILE $(mktemp) || exit 1

bash "$cwd/common.sh" $KONG_ENV_FILE $KONG_ENV_DOWN_FILE

if test $status -ne 0
    echo "Something goes wrong, please check common.sh output"
    return
end

source $KONG_ENV_FILE

function stop_services -d 'Stop dependency services of Kong and clean up environment variables.'
    for i in (cat $KONG_ENV_DOWN_FILE)
      set -e $i
    end
    rm -rf $KONG_ENV_FILE $KONG_ENV_DOWN_FILE
    set -e KONG_ENV_FILE KONG_ENV_DOWN_FILE
    if test -n $docker_compose_file && test -n $docker_compose_project
        docker-compose -f "$docker_compose_file" -p "$docker_compose_project" down
        set -e docker_compose_file docker_compose_project
    end
    functions -e stop_services
end

echo 'Services are up! Use "stop_services" to stop services and cleanup environment variables,
or use "deactivate" to cleanup the venv.'
