local lrucache = require "resty.lrucache"
local ipmatcher = require "resty.ipmatcher"
local kong_meta = require "kong.meta"


local ngx_var = ngx.var
local kong = kong
local error = error


local IPMATCHER_COUNT = 512
local IPMATCHER_TTL   = 3600
local cache = lrucache.new(IPMATCHER_COUNT)


local IpRestrictionHandler = {
  PRIORITY = 990,
  VERSION = kong_meta.version,
}


local isempty
do
  local tb_isempty = require "table.isempty"

  isempty = function(t)
    return t == nil or tb_isempty(t)
  end
end


local function match_bin(list, binary_remote_addr)
  local matcher, err

  matcher = cache:get(list)
  if not matcher then
    matcher, err = ipmatcher.new(list)
    if err then
      return error("failed to create a new ipmatcher instance: " .. err)
    end

    cache:set(list, matcher, IPMATCHER_TTL)
  end

  local is_match
  is_match, err = matcher:match_bin(binary_remote_addr)
  if err then
    return error("invalid binary ip address: " .. err)
  end

  return is_match
end


function IpRestrictionHandler:access(conf)
  local binary_remote_addr = ngx_var.binary_remote_addr
  if not binary_remote_addr then
    return kong.response.error(403, "Cannot identify the client IP address, unix domain sockets are not supported.")
  end

  local deny = conf.deny
  local allow = conf.allow
  local status = conf.status or 403
  local message = conf.message or "Your IP address is not allowed"

  if not isempty(deny) then
    local blocked = match_bin(deny, binary_remote_addr)
    if blocked then
      return kong.response.error(status, message)
    end
  end

  if not isempty(allow) then
    local allowed = match_bin(allow, binary_remote_addr)
    if not allowed then
      return kong.response.error(status, message)
    end
  end
end


return IpRestrictionHandler
