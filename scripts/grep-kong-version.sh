#!/usr/bin/env bash

# unofficial strict mode
set -euo pipefail

kong_version=$(echo kong-*.rockspec | sed 's,.*/,,' | cut -d- -f2)

if test -f "kong/enterprise_edition/meta.lua"; then
    ee_patch=$(grep -o -E 'ee_patch[ \t]+=[ \t]+[0-9]+' kong/enterprise_edition/meta.lua | awk '{print $3}')
    kong_version="$kong_version.$ee_patch"
fi

echo "$kong_version"
