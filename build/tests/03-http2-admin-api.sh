#!/usr/bin/env bash

if [ -n "${VERBOSE:-}" ]; then
    set -x
fi

source .requirements
source build/tests/util.sh

kong_ready

msg_test "Check if cURL supports HTTP/2"
if ! curl --version | grep -i "http2" > /dev/null; then
  err_exit " local cURL does not support HTTP/2"
fi

msg_test "Check HTTP/2 Admin API response is valid"
admin_api_http2_validity
