#!/usr/bin/env fish

set cwd (dirname (status --current-filename))

set -xg docker_compose_file $cwd/docker-compose-test-services.yml
set -xg docker_compose_project kong

set -xg KONG_ENV_FILE .env
set -xg KONG_ENV_DOWN_FILE .env.down

bash "$cwd/common.sh"

if test $status -ne 0
    echo "Something goes wrong, please check common.sh output"
    return
end

source $KONG_ENV_FILE

function stop_services -d 'Stop dependency services of Kong and clean up environment variables.'
    eval "set -e $(cat $KONG_ENV_DOWN_FILE | xargs -d '\n')"
    if test -n $docker_compose_file && test -n $docker_compose_project
        docker-compose -f "$docker_compose_file" -p "$docker_compose_project" down
        set -e docker_compose_file docker_compose_project
    end
    functions -e stop_services
end

echo 'Services are up! Use "stop_services" to stop services and cleanup environment variables,
or use "deactivate" to cleanup the venv.'