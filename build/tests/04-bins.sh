#!/usr/bin/env bash

if [ -n "${VERBOSE:-}" ]; then
    set -x
fi

source .requirements
source build/tests/util.sh

msg_test "Check if Kong provided cURL is executable"
if ! test -x /usr/local/kong/bin/curl; then
  err_exit " cURL not executable"
fi
