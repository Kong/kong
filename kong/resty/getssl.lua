local ffi = require "ffi"
local pushssl = require "openssl.ssl".pushffi -- will define SSL* in ffi
local get_ssl_pointer = require "ngx.ssl".get_ssl_pointer


local getssl
if get_ssl_pointer == nil then
  local err_msg = "OpenResty patch missing. See https://github.com/Kong/openresty-patches"

  ngx.log(ngx.WARN, err_msg)

  function getssl()
    return nil, err_msg
  end
else
  local cast = ffi.cast
  local SSLp = ffi.typeof "SSL*"

  function getssl()
    local ptr, err = get_ssl_pointer()
    if not ptr then
      return nil, err
    end
    ptr = cast(SSLp, ptr)
    return pushssl(ptr)
  end
end


return {
  getssl = getssl,
}
