local iputils = require "resty.iputils"
local responses = require "kong.tools.responses"

local _M = {}

function _M.execute(conf)
  local block = false
  local remote_addr = ngx.var.remote_addr

  if conf._blacklist_cache and #conf._blacklist_cache > 0 then
    block = iputils.ip_in_cidrs(remote_addr, conf._blacklist_cache)
  end

  if conf._whitelist_cache and #conf._whitelist_cache > 0 then
    block = not iputils.ip_in_cidrs(remote_addr, conf._whitelist_cache)
  end

  if block then
    return responses.send_HTTP_FORBIDDEN("Your IP address is not allowed")
  end
end

return _M
