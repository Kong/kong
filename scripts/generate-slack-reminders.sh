#!/usr/bin/env bash
set -eEuo pipefail
shopt -s inherit_errexit

reminder() {
  echo "/remind #team-fast-track scripts/sync-ce-ee -f $1 -t $2 every $3"
}

main() {
  LATEST="next/2.2.x.x"
  reminder "next/2.1.x.x" "next/2.2.x.x" "Friday"
  reminder "next/1.3.0.x" "next/1.5.0.x" "Friday"
  reminder "next/1.5.0.x" "next/2.1.x.x" "Tuesday"
  reminder "$LATEST" "master" "Wednesday"
  reminder "kong:release/2.2.0" "kong-ee:$LATEST" "Thursday"
}

main "$@"
