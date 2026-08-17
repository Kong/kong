
if [ -n "${VERBOSE:-}" ]; then
    set -x
fi

create_user() {

  groupadd -f kong
  useradd -g kong -s /bin/sh -c "Kong default user" kong

  FILES=""
  FILES="${FILES} /etc/kong/"
  FILES="${FILES} /usr/local/bin/json2lua"
  FILES="${FILES} /usr/local/bin/kong"
  FILES="${FILES} /usr/local/bin/lapis"
  FILES="${FILES} /usr/local/bin/lua2json"
  FILES="${FILES} /usr/local/bin/luarocks"
  FILES="${FILES} /usr/local/bin/luarocks-admin"
  FILES="${FILES} /usr/local/bin/openapi2kong"
  FILES="${FILES} /usr/local/etc/luarocks/"
  FILES="${FILES} /usr/local/etc/passwdqc/"
  FILES="${FILES} /usr/local/kong/"
  FILES="${FILES} /usr/local/lib/lua/"
  FILES="${FILES} /usr/local/lib/luarocks/"
  FILES="${FILES} /usr/local/openresty/"
  FILES="${FILES} /usr/local/share/lua/"

  for FILE in ${FILES}; do
    chown -R kong:kong ${FILE}
    chmod -R g=u ${FILE}
  done

  return 0
}

if [ -n "${VERBOSE:-}" ]; then
  create_user
else
  create_user > /dev/null 2>&1
fi
