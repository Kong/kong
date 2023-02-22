#!/usr/bin/env bash

if [ -n "${VERBOSE:-}" ]; then
    set -x
fi

source .requirements
source build/tests/util.sh

service_name="$(random_string)"
route_name="$(random_string)"

kong_ready

msg_test "Check admin API is alive"
assert_response "${KONG_ADMIN_URI}" "200"

msg_test "Create a service"
assert_response "-d name=${service_name} -d url=http://127.0.0.1:8001 ${KONG_ADMIN_URI}/services" "201"

msg_test  "List services"
assert_response "${KONG_ADMIN_URI}/services" "200"

msg_test "Create a route"
assert_response "-d name=${route_name} -d paths=/anything ${KONG_ADMIN_URI}/services/${service_name}/routes" "201"

msg_test "List routes"
assert_response "${KONG_ADMIN_URI}/services/${service_name}/routes" "200"

msg_test "List services"
assert_response "${KONG_ADMIN_URI}/services" "200"

msg_test "Proxy a request"
assert_response "${KONG_PROXY_URI}/anything" "200"

if [[ "$EDITION" == "enterprise" ]]; then
    it_runs_free_enterprise
fi
