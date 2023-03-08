#!/usr/bin/env bash

if [ -n "${VERBOSE:-}" ]; then
    set -x
fi

source .requirements
source build/tests/util.sh

service_name="$(random_string)"
route_name="$(random_string)"

kong_ready

msg_test "Check if cURL supports HTTP/2"
if ! curl --version | grep -i "http2" > /dev/null; then
  msg_yellow "local cURL does not support HTTP/2, bypass HTTP/2 tests"
  exit 0
fi

msg_test "Check HTTP/2 Admin API response is valid"
admin_api_http2_validity
