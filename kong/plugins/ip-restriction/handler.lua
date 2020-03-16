local ngx = ngx
local kong = kong
local require = require

local ipmatcher = require "resty.ipmatcher"


local FORBIDDEN = 403


local IpRestrictionHandler = {}

IpRestrictionHandler.PRIORITY = 990
IpRestrictionHandler.VERSION = "2.0.0"

function IpRestrictionHandler:access(conf)
  local block = false
  local err = false
  local binary_remote_addr = ngx.var.binary_remote_addr
  local ip

  if not binary_remote_addr then
    return kong.response.exit(FORBIDDEN, { message = "Cannot identify the client IP address, unix domain sockets are not supported." })
  end

  if conf.blacklist and #conf.blacklist > 0 then
    ip = ipmatcher.new(conf.blacklist)

    block, err = ip:match_bin(binary_remote_addr)
  end

  if conf.whitelist and #conf.whitelist > 0 then
    ip = ipmatcher.new(conf.whitelist)

    block, err = ip:match_bin(binary_remote_addr)
    block = not block
  end

  if err then
    block = true
    kong.log.err("invalid binary IP address: " .. err)
  end

  if block then
    return kong.response.exit(FORBIDDEN, { message = "Your IP address is not allowed" })
  end
end

return IpRestrictionHandler
