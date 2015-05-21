local responses = require "kong.tools.responses"

local _M = {}

function _M.execute(conf)
  if conf.only_https and ngx.var.scheme:lower() ~= "https" then
    ngx.header["connection"] = { "Upgrade" }
    ngx.header["upgrade"] = "TLS/1.0, HTTP/1.1"
    return responses.send(426, {message="Please use HTTPS protocol"})
  end
end

return _M
