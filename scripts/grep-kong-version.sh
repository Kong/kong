#!/usr/bin/env bash

# unofficial strict mode
set -euo pipefail

kong_version=$(grep -E '^\s*(major|minor|patch)\s*=' kong/meta.lua \
    | sed -E 's/[^0-9]*([0-9]+).*/\1/' \
    | paste -sd. -)

if test -f "kong/enterprise_edition/meta.lua"; then
    ee_patch=$(grep -o -E 'ee_patch[ \t]+=[ \t]+[0-9]+' kong/enterprise_edition/meta.lua | awk '{print $3}')
    kong_version="$kong_version.$ee_patch"
fi

echo "$kong_version"
