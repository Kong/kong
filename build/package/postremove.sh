if [ -n "${VERBOSE:-}" ]; then
    set -x
fi

delete_user() {
  if id "kong" &>/dev/null; then
    userdel kong
  fi

  if getent group "kong" &>/dev/null; then
    groupdel kong
  fi

  FILES=""
  FILES="${FILES} /etc/kong"
  FILES="${FILES} /usr/local/lib/luarocks/rocks-5.1/kong"
  FILES="${FILES} /usr/local/share/lua/5.1/kong"
  FILES="${FILES} /usr/local/kong"
  FILES="${FILES} /usr/local/openresty/lualib/resty/kong"
  FILES="${FILES} /var/spool/mail/kong"

  for FILE in ${FILES}; do
    rm -rf ${FILE}
  done

  return 0
}

if [ -n "${VERBOSE:-}" ]; then
  delete_user
else
  delete_user > /dev/null 2>&1
fi
