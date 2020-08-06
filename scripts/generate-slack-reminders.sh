#!/usr/bin/env bash
set -eEuo pipefail
shopt -s inherit_errexit

reminder() {
  echo "/remind #team-fast-track scripts/sync-ce-ee -f $1 -t $2 every $3"
}
main() {
  reminder "next/1.3.0.x" "next/1.5.0.x" "Friday"
  reminder "next/1.5.0.x" "next/2.1.0.x" "Tuesday"
  reminder "next/2.1.0.x" "master" "Wednesday"
  reminder "kong:master" "kong-ee:next/2.1.0.x" "Thursday"
}

main "$@"
