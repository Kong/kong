local ssl_util = require "kong.plugins.ssl.ssl_util"
local cache = require "kong.tools.database_cache"

local _M = {}

function _M.execute(conf)
  local ssl = require "ngx.ssl"
  ssl.clear_certs()

  local data = cache.get_and_set(cache.ssl_data(ngx.ctx.api.id), function()
    local result = {
      cert_der = ngx.decode_base64(conf.cert_der),
      key_der = ngx.decode_base64(conf.key_der)
    }
    return result
  end)

  local ok, err = ssl.set_der_cert(data.cert_der)
  if not ok then
    ngx.log(ngx.ERR, "failed to set DER cert: ", err)
    return
  end
  local ok, err = ssl.set_der_priv_key(data.key_der)
  if not ok then
    ngx.log(ngx.ERR, "failed to set DER private key: ", err)
    return
  end
end

return _M
