#!/usr/bin/env bash
set -eEuo pipefail
shopt -s inherit_errexit

reminder() {
  echo "/remind #team-fast-track scripts/sync-ce-ee -f $1 -t $2 every $3"
}

main() {
  LATEST="next/2.1.x.x"
  reminder "next/1.3.0.x" "next/1.5.0.x" "Friday"
  reminder "next/1.5.0.x" "$LATEST" "Tuesday"
  reminder "$LATEST" "master" "Wednesday"
  reminder "kong:master" "kong-ee:$LATEST" "Thursday"
}

main "$@"
