local cjson = require "cjson.safe"
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


local function do_exit(status, message, is_http)
  if is_http then
    return kong.response.error(status, message)

  else
    local tcpsock, err = ngx.req.socket(true)
    if err then
      error(err)
    end

    local response = cjson.encode({
      status  = status,
      message = message
    })

    tcpsock:send(response)

    return ngx.exit()
  end
end


local function handler(conf, is_http)
  local binary_remote_addr = ngx_var.binary_remote_addr
  if not binary_remote_addr then
    local status = 403
    local message = "Cannot identify the client IP address, unix domain sockets are not supported."

    do_exit(status, message, is_http)
  end

  local deny = conf.deny
  local allow = conf.allow
  local status = conf.status or 403
  local default_message = string.format("IP address not allowed: %s", binary_remote_addr)
  local message = conf.message or default_message

  if not isempty(deny) then
    local blocked = match_bin(deny, binary_remote_addr)
    if blocked then
      do_exit(status, message, is_http)
    end
  end

  if not isempty(allow) then
    local allowed = match_bin(allow, binary_remote_addr)
    if not allowed then
      do_exit(status, message, is_http)
    end
  end
end


function IpRestrictionHandler:access(conf)
  return handler(conf, true)
end


function IpRestrictionHandler:preread(conf)
  return handler(conf, false)
end


return IpRestrictionHandler
