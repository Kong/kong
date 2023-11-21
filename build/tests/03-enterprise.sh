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

###
#
# Enterprise-only
#
###

# 2.8 does not have expat
for library in \
  jq \
  passwdqc \
  license_utils; do
  msg_test "${library} library exists, is not empty, and is readable by kong user"
  assert_exec 0 'kong' "test -s /usr/local/kong/lib/lib${library}.so"

  msg_test "resty CLI can ffi load ${library} library"
  assert_exec 0 'kong' "/usr/local/openresty/bin/resty -e 'require(\"ffi\").load \"${library}\"'"
done

msg_test "nettle libraries exists, are not empty, and are readable by kong user"
assert_exec 0 'kong' "test -s /usr/local/kong/lib/libnettle.so"
assert_exec 0 'kong' "test -s /usr/local/kong/lib/libhogweed.so"

msg_test "resty CLI can ffi load nettle libraries"
assert_exec 0 'kong' "/usr/local/openresty/bin/resty -e 'require(\"ffi\").load \"nettle\"'"
assert_exec 0 'kong' "/usr/local/openresty/bin/resty -e 'require(\"ffi\").load \"hogweed\"'"

# 2.8 does not have xml2/xslt
# msg_test "xml libraries exists, are not empty, and are readable by kong user"
# assert_exec 0 'kong' "test -s /usr/local/kong/lib/libxml2.so"
# assert_exec 0 'kong' "test -s /usr/local/kong/lib/libxslt.so"

# msg_test "resty CLI can ffi load xml libraries"
# assert_exec 0 'kong' "/usr/local/openresty/bin/resty -e 'require(\"ffi\").load \"xml2\"'"
# assert_exec 0 'kong' "/usr/local/openresty/bin/resty -e 'require(\"ffi\").load \"xslt\"'"
