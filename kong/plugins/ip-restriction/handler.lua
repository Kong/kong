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
    return kong.response.exit(403, { message = "Cannot identify the client IP address, unix domain sockets are not supported." })
  end

  if conf.blacklist and #conf.blacklist > 0 then
    local blocked_blacklist = match_bin(conf.blacklist, binary_remote_addr)
    if blocked_blacklist then
      return kong.response.exit(403, { message = "Your IP address is not allowed" })
    end
  end

  if conf.whitelist and #conf.whitelist > 0 then
    local allowed_whitelist = match_bin(conf.whitelist, binary_remote_addr)
    if not allowed_whitelist then
      return kong.response.exit(403, { message = "Your IP address is not allowed" })
    end
  end
end


return IpRestrictionHandler
