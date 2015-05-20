local resolver_util = require("kong.resolver.resolver_util")

local _M = {}

function _M.execute(conf)
  local ssl = require "ngx.ssl"
  local server_name = ssl.server_name()
  if server_name then -- Only support SNI requests
    local api, err = resolver_util.find_api({server_name})
    if not err and api then
      ngx.ctx.api = api
    end
  end
end

return _M
