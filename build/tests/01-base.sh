#!/usr/bin/env bash

if [ -n "${VERBOSE:-}" ]; then
    set -x
fi

source .requirements
source build/tests/util.sh

###
#
# user/group
#
###

# a missing kong user can indicate that the post-install script on rpm/deb
# platforms failed to run properly
msg_test '"kong" user exists'
assert_exec 0 'root' 'getent passwd kong'

msg_test '"kong" group exists'
assert_exec 0 'root' 'getent group kong'

###
#
# files and ownership
#
###

msg_test "/usr/local/kong exists and is owned by kong:root"
assert_exec 0 'kong' "test -O /usr/local/kong || ( rc=\$?; stat '${path}'; exit \$rc )"
assert_exec 0 'root' "test -G /usr/local/kong || ( rc=\$?; stat '${path}'; exit \$rc )"

msg_test "/usr/local/bin/kong exists and is owned by kong:root"
assert_exec 0 'kong' "test -O /usr/local/kong || ( rc=\$?; stat '${path}'; exit \$rc )"
assert_exec 0 'root' "test -G /usr/local/kong || ( rc=\$?; stat '${path}'; exit \$rc )"

if alpine; then
    # we have never produced real .apk package files for alpine and thus have
    # never depended on the kong user/group chown that happens in the
    # postinstall script(s) for other package types
    #
    # if we ever do the work to support real .apk files (with read postinstall
    # scripts), we will need to this test
    msg_yellow 'skipping file and ownership tests on alpine'
else
    for path in \
        /usr/local/bin/luarocks \
        /usr/local/etc/luarocks/ \
        /usr/local/lib/{lua,luarocks}/ \
        /usr/local/openresty/ \
        /usr/local/share/lua/; do
        msg_test "${path} exists and is owned by kong:kong"
        assert_exec 0 'kong' "test -O ${path} || ( rc=\$?; stat '${path}'; exit \$rc )"
        assert_exec 0 'kong' "test -G ${path} || ( rc=\$?; stat '${path}'; exit \$rc )"
    done
fi

msg_test 'default conf file exists and is not empty'
assert_exec 0 'root' "test -s /etc/kong/kong.conf.default"

msg_test 'default logrotate file exists and is not empty'
assert_exec 0 'root' "test -s /etc/kong/kong.logrotate"

msg_test 'plugin proto file exists and is not empty'
assert_exec 0 'root' "test -s /usr/local/kong/include/kong/pluginsocket.proto"

msg_test 'protobuf files exist and are not empty'
assert_exec 0 'root' "for f in /usr/local/kong/include/google/protobuf/*.proto; do test -s \$f; done"

msg_test 'ssl header files exist and are not empty'
assert_exec 0 'root' "for f in /usr/local/kong/include/openssl/*.h; do test -s \$f; done"

###
#
# OpenResty binaries/tools
#
###

msg_test 'openresty binary is expected version'
assert_exec 0 'root' "/usr/local/openresty/bin/openresty -v 2>&1 | grep '${RESTY_VERSION}'"

# linking to a non-kong-provided luajit library can indicate the package was
# created on a dev workstation where luajit/openresty was installed manually
# and probably shouldn't be shipped to customers
msg_test 'openresty binary is linked to kong-provided luajit library'
assert_exec 0 'root' "ldd /usr/local/openresty/bin/openresty | grep -E 'libluajit-.*openresty/luajit/lib'"

# if libpcre appears in the ldd output for the openresty binary, static linking
# of it during the compile of openresty may have failed
msg_test 'openresty binary is NOT linked to external PCRE'
assert_exec 0 'root' "ldd /usr/local/openresty/bin/openresty | grep -ov 'libpcre.so'"

msg_test 'openresty binary compiled with LuaJIT PCRE support'
assert_exec 0 'root' "/usr/local/openresty/bin/openresty -V 2>&1 | grep '\-\-with-pcre-jit'"

msg_test 'resty CLI can be run by kong user'
assert_exec 0 'kong' "/usr/local/openresty/bin/resty -e 'print(jit.version)'"

msg_test 'resty CLI functions and returns valid version of LuaJIT'
assert_exec 0 'root' "/usr/local/openresty/bin/resty -e 'print(jit.version)' | grep -E 'LuaJIT\ ([0-9]\.*){3}\-20[0-9]+'"

###
#
# SSL verification
#
###

# check which ssl openresty is using
if docker_exec root '/usr/local/openresty/bin/openresty -V 2>&1' | grep 'BoringSSL'; then
    msg_test 'openresty binary uses expected boringssl version'
    assert_exec 0 'root' "/usr/local/openresty/bin/openresty -V 2>&1 | grep '${RESTY_BORINGSSL_VERSION}'"
else
    msg_test 'openresty binary uses expected openssl version'
    assert_exec 0 'root' "/usr/local/openresty/bin/openresty -V 2>&1 | grep '${RESTY_OPENSSL_VERSION}'"
fi

msg_test 'openresty binary is linked to kong-provided ssl libraries'
assert_exec 0 'root' "ldd /usr/local/openresty/bin/openresty | grep -E 'libssl.so.*kong/lib'"
assert_exec 0 'root' "ldd /usr/local/openresty/bin/openresty | grep -E 'libcrypto.so.*kong/lib'"

###
#
# LuaRocks
#
###

msg_test 'lua-resty-websocket lua files exist and contain a version'
assert_exec 0 'root' 'grep _VERSION /usr/local/openresty/lualib/resty/websocket/*.lua'
