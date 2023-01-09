#!/usr/bin/env bash
set -e

function red() {
    echo -e "\033[1;31m$*\033[0m"
}

EE_PLUGIN_LIST=$(find ./plugins-ee -maxdepth 2 -name '*.rockspec' | grep -Eo './plugins-ee/([^/]+)' | awk -F '/' '{print $3}')

EE_BUNDLED_LIST=$(resty -e 'require("kong.globalpatches")({cli = true}) local dist_constants = require "distribution.distributions_constants" for k, v in pairs(dist_constants.plugins) do print(v) end')

NON_BUNDLED_PLUGINS=(app-dynamics)

readarray -t FOUND < \
<(
    echo "$EE_PLUGIN_LIST" | grep -vE -w -f <(echo "$EE_BUNDLED_LIST") | grep -vE -w $(echo "${NON_BUNDLED_PLUGINS[@]}" | tr ' ' '|')
)

if (( ${#FOUND[@]} > 0 )); then
    echo
    red "----------------------------------------------------------------"
    red "Found installed plugins that are not bundled by default:"
    for plugin in "${FOUND[@]}"; do
        red "$plugin"
    done
    red "----------------------------------------------------------------"
    exit 1
fi
