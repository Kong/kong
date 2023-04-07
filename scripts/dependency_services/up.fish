#!/usr/bin/env fish

set cwd (dirname (status --current-filename))

set -xg docker_compose_file $cwd/docker-compose-test-services.yml
set -xg docker_compose_project kong

docker-compose -f "$docker_compose_file" -p "$docker_compose_project" up -d

if test $status -ne 0
    echo "Something goes wrong, please check docker-compose output"
    return
end

# [service_name_in_docker_compose]="env_var_name_1:port_1_in_docker_compose env_var_name_2:port_2_in_docker_compose"
set ports "postgres:PG_PORT:5432" "cassandra:CASSANDRA_PORT:9042" "redis:REDIS_PORT:6379" "redis:REDIS_SSL_PORT:6380" "grpcbin:GRPCBIN_PORT:9000" "grpcbin:GRPCBIN_SSL_PORT:9001" "zipkin:ZIPKIN_PORT:9411"

set -xg kong_added_envs

# not all env variable needs all three prefix in all times, but we add all of them
# for simplicity: there's no side effect after all
set env_prefixes KONG_ KONG_TEST_ KONG_SPEC_TEST_

for svc_port_def in $ports
    set svc (echo $svc_port_def |cut -d: -f1)
    set env_name (echo $svc_port_def |cut -d: -f2)
    set private_port (echo $svc_port_def |cut -d: -f3)
    set exposed_port (docker-compose -f "$docker_compose_file" -p "$docker_compose_project" port $svc $private_port | cut -d: -f2)
    if test -z $exposed_port
        echo "Port $env_name for service $svc unknown"
        continue
    end
    for prefix in $env_prefixes
        set -a kong_added_envs $prefix$env_name
        eval "set -xg $prefix$env_name $exposed_port"
    end
end

function stop_services -d 'Stop dependency services of Kong and clean up environment variables.'
    for v in $kong_added_envs
        eval "set -e $v"
    end

    set -e kong_added_envs
    if test -n $docker_compose_file && test -n $docker_compose_project
        docker-compose -f "$docker_compose_file" -p "$docker_compose_project" down
        set -e docker_compose_file docker_compose_project
    end
    functions -e stop_services
end

echo 'Services are up! Use "stop_services" to stop services and cleanup environment variables,
or use "deactivate" to cleanup the venv.'