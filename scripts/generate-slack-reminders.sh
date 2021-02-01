#!/usr/bin/env bash
set -eEuo pipefail
shopt -s inherit_errexit

reminder() {
  echo "/remind #team-fast-track scripts/sync-ce-ee -f $1 -t $2 every $3"
}

main() {
  LATEST="next/2.3.x.x"
  reminder "next/1.3.0.x" "next/1.5.0.x" "Monday"
  reminder "next/1.5.0.x" "next/2.1.x.x" "Tuesday"
  reminder "next/2.1.x.x" "next/2.2.x.x" "Wednesday"
  reminder "next/2.2.x.x" "next/2.3.x.x" "Wednesday"
  reminder "kong:master" "next/2.3.x.x" "Thursday"
#  reminder "kong:next" "kong-ee:$LATEST" "Thursday"
  reminder "$LATEST" "master" "Friday"
}

main "$@"
