#!/usr/bin/env bash

KONG_ADMIN_URI=${KONG_ADMIN_URI:-"http://localhost:8001"}
KONG_ADMIN_HTTP2_URI=${KONG_ADMIN_HTTP2_URI:-"https://localhost:8444"}
KONG_PROXY_URI=${KONG_PROXY_URI:-"http://localhost:8000"}

set_x_flag=''
if [ -n "${VERBOSE:-}" ]; then
    set -x
    set_x_flag='-x'
fi

msg_test() {
  builtin echo -en "\033[1;34m" >&1
  echo -n "===> "
  builtin echo -en "\033[1;36m" >&1
  echo -e "$@"
  builtin echo -en "\033[0m" >&1
}

msg_red() {
  builtin echo -en "\033[1;31m" >&2
  echo -e "$@"
  builtin echo -en "\033[0m" >&2
}

msg_yellow() {
  builtin echo -en "\033[1;33m" >&1
  echo -e "$@"
  builtin echo -en "\033[0m" >&1
}

err_exit() {
  msg_red "$@"
  exit 1
}

random_string() {
  echo "a$(shuf -er -n19  {A..Z} {a..z} {0..9} | tr -d '\n')"
}

kong_ready() {
  local TIMEOUT_SECONDS=$((15))
  while [[ "$(curl -s -o /dev/null -w "%{http_code}" localhost:8000)" != 404 ]]; do
    sleep 5;
    COUNTER=$((COUNTER + 5))

    if (( COUNTER >= TIMEOUT_SECONDS ))
    then
      printf '\xe2\x98\x93 ERROR: Timed out waiting for %s' "$KONG"
      exit 1
    fi
  done
}

docker_exec() {
  local user="${1:-kong}"

  shift

  test -t 1 && USE_TTY='-t'

  # shellcheck disable=SC2086
  docker exec --user="$user" ${USE_TTY} kong sh ${set_x_flag} -c "$@"
}

_os() {
  local os="$1"

  if docker_exec 'root' 'uname -a' | grep -qsi "$os"; then
    return
  else
    docker_exec 'root' "grep -qsi '${os}' /etc/os-release"
    return $?
  fi
}

alpine() {
  _os 'alpine'
}

assert_same() {
  local expected=$(echo "$1" | tr -d '[:space:]')
  local actual=$(echo "$2" | tr -d '[:space:]')

  if [ "$expected" != "$actual" ]; then
    err_exit "  expected $expected, got $actual"
  fi
}

assert_contains() {
  local expected=$(echo "$1" | tr -d '[:space:]')
  local actual="$2"

  if ! echo "$actual" | grep -q "$expected"; then
    err_exit "  expected $expected in $actual but not found"
  fi
}

assert_response() {
  local endpoint=$1
  local expected_codes=$2
  local resp_code
  COUNTER=20
  while : ; do
    for code in ${expected_codes}; do
      # shellcheck disable=SC2086
      resp_code=$(curl -s -o /dev/null -w "%{http_code}" ${endpoint})
      [ "$resp_code" == "$code" ] && break 2
    done
    ((COUNTER-=1))
    [ "$COUNTER" -lt 1 ] && break
    sleep 0.5 # 10 seconds max
  done
  for code in ${expected_codes}; do
    [ "$resp_code" == "$code" ] && return
  done || err_exit "  expected $2, got $resp_code"
}

assert_exec() {
  local expected_code="${1:-0}"
  local user="${2:-kong}"

  shift 2

  (
    docker_exec "$user" "$@"
    echo "$?" > /tmp/rc
  ) | while read -r line; do printf '  %s\n' "$line"; done

  rc="$(cat /tmp/rc)"

  if ! [ "$rc" == "$expected_code" ]; then
    err_exit "  expected ${expected_code}, got ${rc}"
  fi
}

it_runs_free_enterprise() {
  info=$(curl "$KONG_ADMIN_URI")
  msg_test "it does not have ee-only plugins"
  [ "$(echo "$info" | jq -r .plugins.available_on_server.canary)" != "true" ]
  msg_test "it does not enable vitals"
  [ "$(echo "$info" | jq -r .configuration.vitals)" == "false" ]
  msg_test "workspaces are not writable"
  assert_response "$KONG_ADMIN_URI/workspaces -d name=$(random_string)" "403"
}

it_runs_full_enterprise() {
  info=$(curl "$KONG_ADMIN_URI")
  msg_test "it does have ee-only plugins"
  [ "$(echo "$info" | jq -r .plugins.available_on_server | jq -r 'has("canary")')" == "true" ]
  msg_test "it does enable vitals"
  [ "$(echo "$info" | jq -r .configuration.vitals)" == "true" ]
  msg_test "workspaces are writable"
  assert_response "$KONG_ADMIN_URI/workspaces -d name=$(random_string)" "201"
}

admin_api_http2_validity() {
  output=$(mktemp)
  header_dump=$(mktemp)
  status=$(curl -ks -D "$header_dump" -o "$output" -w '%{http_code}' "$KONG_ADMIN_HTTP2_URI")

  msg_test "it returns with response status code 200"
  assert_same "200" "$status"

  msg_test "it returns with response header content-type application/json"
  assert_contains "application/json" "$(cat "$header_dump" | grep -i content-type | tr -d '[:space:]')"

  msg_test "it returns a response body with correct length"
  assert_same "$(wc -c < "$output")" "$(cat "$header_dump" | grep -i content-length | cut -d' ' -f2 | tr -d '[:space:]')"

  msg_test "the response body is valid json and has valid json schema"
  jq . "$output" > /dev/null || err_exit "  response body is not valid json"
}
