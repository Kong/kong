#!/usr/bin/env bash
set -e

function red() {
    echo -e "\033[1;31m$*\033[0m"
}

readarray -t FOUND < \
<(
  git ls-files 'spec/[0-9]**.lua' \
  | grep -vE \
    -e '_spec.lua$' \
    -f spec/on_demand_specs
)

if (( ${#FOUND[@]} > 0 )); then
  echo
  red "----------------------------------------------------------------"
  echo "Found some files in spec directory that do not have the _spec suffix, please check if you're misspelling them. If there is an exception, please add the coressponding files(or their path regexes) into the whitelist spec/on_demand_specs."
  echo
  echo "Possible misspelling file list:"
  echo
  printf "%s\n" "${FOUND[@]}"
  red "----------------------------------------------------------------"
  exit 1
fi
