local cjson = require "cjson"
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


local function do_exit(status, message, is_http)
  if is_http then
    return kong.response.error(status, message)
  else
    local tcpsock, err = ngx.req.socket(true)
    if err then
      error(err)
    end

    tcpsock:send(cjson.encode({
      status  = status,
      message = message
    }))

    return ngx.exit()
  end
end


local function handler(conf, is_http)
  local binary_remote_addr = ngx.var.binary_remote_addr
  if not binary_remote_addr then
    local status = 403
    local message = "Cannot identify the client IP address, unix domain sockets are not supported."

    do_exit(status, message, is_http)
  end

  local status = conf.status or 403
  local message = conf.message or string.format("IP address not allowed: %s", ngx.var.remote_addr)

  if conf.deny and #conf.deny > 0 then
    local blocked = match_bin(conf.deny, binary_remote_addr)

    if blocked then
      do_exit(status, message, is_http)
    end
  end

  if conf.allow and #conf.allow > 0 then
    local allowed = match_bin(conf.allow, binary_remote_addr)

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
