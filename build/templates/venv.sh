#!/bin/bash

# template variables starts
build_name="{{build_name}}"
workspace_path="{{workspace_path}}"
# template variables ends

KONG_VENV="$workspace_path/bazel-bin/build/$build_name"
export KONG_VENV

# set PATH
if [ -n "${_OLD_KONG_VENV_PATH}" ]; then
    # restore old PATH first, if this script is called multiple times
    PATH="${_OLD_KONG_VENV_PATH}"
else
    _OLD_KONG_VENV_PATH="${PATH}"
fi
export PATH

deactivate () {
    export PATH="${_OLD_KONG_VENV_PATH}"
    export PS1="${_OLD_KONG_VENV_PS1}"
    unset KONG_VENV
    unset _OLD_KONG_VENV_PATH _OLD_KONG_VENV_PS1
    unset ROCKS_CONFIG ROCKS_ROOT LUAROCKS_CONFIG LUA_PATH LUA_CPATH KONG_PREFIX LIBRARY_PREFIX OPENSSL_DIR

    type stop_services >/dev/null && stop_services

    unset -f deactivate
    unset -f start_services
}

start_services () {
    source $workspace_path/scripts/dependency_services/up.sh
    # stop_services is defined by the script above
}

# actually set env vars
. ${KONG_VENV}-venv/lib/venv-commons

# set shell prompt
if [ -z "${KONG_VENV_DISABLE_PROMPT-}" ] ; then
    if [ -n "${_OLD_KONG_VENV_PS1}" ]; then
        # prepend the old PS1 if this script is called multiple times
        PS1="(${build_name}) ${_OLD_KONG_VENV_PS1}"
    else
        _OLD_KONG_VENV_PS1="${PS1-}"
        PS1="(${build_name}) ${PS1-}"
    fi
    export PS1
fi

# check wrapper
test -n "$*" && exec "$@" || true
