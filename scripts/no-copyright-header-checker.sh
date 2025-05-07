#!/usr/bin/env bash

set -e

LOCAL_PATH="$(dirname "$(realpath "$0")")"

check_copyright_header_lua_files() {
  local path="$1"
  local sha=$(cat "$LOCAL_PATH/COPYRIGHT-HEADER-SHA")

  mapfile -t -d '' files \
    < <(git -C "$path" ls-files -z '**/*.lua')

  if (( ${#files[@]} < 1000 )); then
    >&2 echo "Only ${#files[@]} lua files were found, but we expected" \
             "there to be a lot more. If this is expected, update the script."
    exit 1
  fi

  local found=0
  for file in "${files[@]}"; do
    if grep -Fq "$sha" "$file"; then
      >&2 printf "File %s has the copyright header\n" "$file"
      found=1
    fi
  done

  if [ "$found" -eq 1 ]; then
    exit 1
  fi
}

check_copyright_header_lua_files "$(realpath "$LOCAL_PATH"/..)"
