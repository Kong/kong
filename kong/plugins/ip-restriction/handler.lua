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

  if not binary_remote_addr then
    return kong.response.exit(FORBIDDEN, { message = "Cannot identify the client IP address, unix domain sockets are not supported." })
  end

  if conf.blacklist and #conf.blacklist > 0 then
    if not kong.ctx.plugin.blacklist then
      kong.ctx.plugin.blacklist = ipmatcher.new(conf.blacklist)
    end

    block, err = kong.ctx.plugin.blacklist:match_bin(binary_remote_addr)
  end

  if conf.whitelist and #conf.whitelist > 0 then
    if not kong.ctx.plugin.whitelist then
      kong.ctx.plugin.whitelist = ipmatcher.new(conf.whitelist)
    end

    block, err = kong.ctx.plugin.whitelist:match_bin(binary_remote_addr)
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
