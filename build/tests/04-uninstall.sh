#!/usr/bin/env bash

if [ -n "${VERBOSE:-}" ]; then
    set -x
fi

source .requirements
source build/tests/util.sh

remove_kong_command() {
    local pkg_name=""
    local remove_cmd=""

    case "${BUILD_LABEL}" in
        "ubuntu"| "debian")
            remove_cmd="apt-get remove -y kong"
            ;;
        "rhel")
            remove_cmd="yum remove -y kong"
            ;;
        *)
            return 1
    esac

    echo "$remove_cmd"
}

msg_test '"kong" remove command'

remove_command=$(remove_kong_command)
if [ $? -eq 0 ]; then
    docker_exec root "$remove_command"
else
    err_exit "can not find kong package"
fi

# kong would create include and lib directory in /usr/local/kong
# but in ubuntu, kong would use /usr/local/kong as default prefix
# so after remove kong, /usr/local/kong would left logs and conf files
# we only check /usr/local/kong/include and /usr/local/kong/lib
msg_test "/usr/local/kong/include has been removed after uninstall"
assert_exec 1 'kong' "test -d /usr/local/kong/include"

msg_test "/usr/local/kong/lib has been removed after uninstall"
assert_exec 1 'kong' "test -d /usr/local/kong/lib"

# if /usr/local/share/lua/5.1 has other files, it will not be removed
# only remove files which are installed by kong
msg_test "/usr/local/share/lua/5.1 has been removed after uninstall"
assert_exec 1 'kong' "test -d /usr/local/share/lua/5.1"

msg_test "/usr/local/openresty has been removed after uninstall"
assert_exec 1 'kong' "test -d /usr/local/openresty"
