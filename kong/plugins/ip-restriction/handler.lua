local ipmatcher = require "resty.ipmatcher"


local ngx = ngx
local kong = kong
local error = error


local IpRestrictionHandler = {
  PRIORITY = 990,
  VERSION = "2.0.0",
}


local function match_bin(list, binary_remote_addr)
  local ip, err = ipmatcher.new(list)
  if err then
    return error("failed to create a new ipmatcher instance: " .. err)
  end

  local is_match
  is_match, err = ip:match_bin(binary_remote_addr)
  if err then
    return error("invalid binary ip address: " .. err)
  end

  return is_match
end


function IpRestrictionHandler:access(conf)
  local binary_remote_addr = ngx.var.binary_remote_addr
  if not binary_remote_addr then
    return kong.response.error(403, "Cannot identify the client IP address, unix domain sockets are not supported.")
  end

  if conf.deny and #conf.deny > 0 then
    local blocked = match_bin(conf.deny, binary_remote_addr)
    if blocked then
      return kong.response.error(403, "Your IP address is not allowed")
    end
  end

  if conf.allow and #conf.allow > 0 then
    local allowed = match_bin(conf.allow, binary_remote_addr)
    if not allowed then
      return kong.response.error(403, "Your IP address is not allowed")
    end
  end
end


return IpRestrictionHandler
