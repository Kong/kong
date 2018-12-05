local ffi = require "ffi"
local openssl = require "openssl.ssl"
local ngx_ssl = require "ngx.ssl"


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
    local ptr, err = ngx_ssl.get_ssl_pointer()
    if not ptr then
      return nil, err
    end
    ptr = cast(SSLp, ptr)
    return openssl.pushssl(ptr)
  end
end


return {
  getssl = getssl,
}
