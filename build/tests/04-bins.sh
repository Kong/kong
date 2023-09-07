#!/usr/bin/env bash

if [ -n "${VERBOSE:-}" ]; then
    set -x
fi

source .requirements
source build/tests/util.sh

msg_test "Check if Kong provided cURL is executable"
assert_exec 0 'root' "test -x /usr/local/kong/bin/curl"

msg_test "Check if Kong provided cURL runs correctly"
assert_exec 0 'root' "/usr/local/kong/bin/curl --version"

msg_test "Check if Kong provided cURL supports HTTP/2"
assert_exec 0 'root' "/usr/local/kong/bin/curl --version | grep -E 'Features:.*HTTP2'"
