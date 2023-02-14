#!/usr/bin/env bash

if [ -n "${VERBOSE:-}" ]; then
  set -x
fi

source .requirements
source build/tests/util.sh

if [[ "$EDITION" != "enterprise" ]]; then
  exit 0
fi

KONG_LICENSE_URL="https://download.konghq.com/internal/kong-gateway/license.json"
KONG_LICENSE_DATA="$(
  curl \
    --silent \
    --location \
    --retry 3 \
    --retry-delay 3 \
    --user "$PULP_USERNAME:$PULP_PASSWORD" \
    --url "$KONG_LICENSE_URL"
)"
export KONG_LICENSE_DATA

if [[ ! $KONG_LICENSE_DATA == *"signature"* || ! $KONG_LICENSE_DATA == *"payload"* ]]; then
  # the check above is a bit lame, but the best we can do without requiring
  # yet more additional dependenies like jq or similar.
  msg_yellow "failed to download the Kong Enterprise license file!
    $KONG_LICENSE_DATA"
fi

F=$(mktemp)
echo "$KONG_LICENSE_DATA" >$F

assert_response "-F payload=@$F $KONG_ADMIN_URI/licenses" "201 409"

rm $F

sleep 1

it_runs_full_enterprise
