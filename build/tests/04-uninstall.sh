#!/usr/bin/env bash

if [ -n "${VERBOSE:-}" ]; then
    set -x
fi

source .requirements
source build/tests/util.sh

remove_kong_command() {
    local pkg_name=""
    local remove_cmd=""

    case "${PACKAGE_TYPE}" in
        "deb")
            pkg_name=$(dpkg -l | grep -i kong | awk '{print $2}')
            remove_cmd="apt-get remove -y $pkg_name"
            ;;
        "rpm")
            pkg_name=$(rpm -qa | grep -i kong)
            remove_cmd="yum remove -y $pkg_name"
            ;;
        "apk")
            pkg_name=$(apk info | grep -i kong)
            remove_cmd="apk del $pkg_name"
            ;;
        *)
            return 1
    esac

    echo "$remove_cmd"
}

msg_test '"kong" remove command'

remove_command=$(remove_kong_command)
if [ $? -eq 0 ]; then
    assert_exec 0 'root' $remove_command
else
    err_exit "can not find kong package"
fi

msg_test "/usr/local/kong does not exist after uninstall"
assert_exec 1 'kong' "test -d /usr/local/kong"
