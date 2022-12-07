#!/usr/bin/env bash
set -e

function red() {
    echo -e "\033[1;31m$*\033[0m"
}

NO_SPEC_FILES=$(find spec -type f -name "*.lua" | grep -E 'spec/[0-9]+-.*' | grep -v "_spec.lua")
WHITELIST_PATTERNS=$(grep -v -E '^#' ./spec/on_demand_specs)
RESULT_TMP=$(mktemp)
RET=0

for file in $NO_SPEC_FILES; do
  passed=0
  for pattern in $WHITELIST_PATTERNS; do
    if grep -q -E "$pattern" <<< "$file"; then
      passed=1
      break
    fi
  done

  if [ $passed -eq 0 ]; then
    RET=1
    echo "$file" >> $RESULT_TMP
  fi
done

if [ $RET -eq 1 ]; then
  echo
  red "----------------------------------------------------------------"
  echo "Found some files in spec directory that do not have the _spec suffix, please check if you're misspelling them. If there is an exception, please add the coressponding files(or their path regexes) into the whitelist spec/on_demand_specs."
  echo
  echo "Possible misspelling file list:"
  cat $RESULT_TMP
  red "----------------------------------------------------------------"
fi

exit $RET
