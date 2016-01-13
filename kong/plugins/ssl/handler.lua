-- Copyright (C) Mashape, Inc.

local BasePlugin = require "kong.plugins.base_plugin"
local responses = require "kong.tools.responses"
local cache = require "kong.tools.database_cache"

local SSLHandler = BasePlugin:extend()

SSLHandler.PRIORITY = 3000

local HTTPS = "https"

local function is_https(conf)
  local result = ngx.var.scheme:lower() == HTTPS
  if not result and conf.accept_http_if_already_terminated then
    local forwarded_proto_header = ngx.req.get_headers()["x-forwarded-proto"]
    result = forwarded_proto_header and forwarded_proto_header:lower() == HTTPS
  end
  return result
end

function SSLHandler:new()
  SSLHandler.super.new(self, "ssl")
end

function SSLHandler:certificate(conf)
  SSLHandler.super.certificate(self)
  local ssl = require "ngx.ssl"
  ssl.clear_certs()

  local data = cache.get_or_set(cache.ssl_data(ngx.ctx.api.id), function()
    local result = {
      cert_der = ngx.decode_base64(conf._cert_der_cache),
      key_der = ngx.decode_base64(conf._key_der_cache)
    }
    return result
  end)

  local ok, err = ssl.set_der_cert(data.cert_der)
  if not ok then
    ngx.log(ngx.ERR, "failed to set DER cert: ", err)
    return
  end
  ok, err = ssl.set_der_priv_key(data.key_der)
  if not ok then
    ngx.log(ngx.ERR, "failed to set DER private key: ", err)
    return
  end
end

function SSLHandler:access(conf)
  SSLHandler.super.access(self)
  if conf.only_https and not is_https(conf) then
    ngx.header["connection"] = { "Upgrade" }
    ngx.header["upgrade"] = "TLS/1.0, HTTP/1.1"
    return responses.send(426, {message="Please use HTTPS protocol"})
  end
end

return SSLHandler
