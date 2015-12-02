local responses = require "kong.tools.responses"

local _M = {}

local HTTPS = "https"

local function is_https(conf)
  local result = ngx.var.scheme:lower() == HTTPS
  if not result and conf.accept_http_if_already_terminated then
    local forwarded_proto_header = ngx.req.get_headers()["x-forwarded-proto"]
    result = forwarded_proto_header and forwarded_proto_header:lower() == HTTPS
  end
  return result
end

function _M.execute(conf)
  if conf.only_https and not is_https(conf) then
    ngx.header["connection"] = { "Upgrade" }
    ngx.header["upgrade"] = "TLS/1.0, HTTP/1.1"
    return responses.send(426, {message="Please use HTTPS protocol"})
  end
end

return _M
