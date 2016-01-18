local BasePlugin = require "kong.plugins.base_plugin"
local responses = require "kong.tools.responses"
local iputils = require "resty.iputils"

local IpRestrictionHandler = BasePlugin:extend()

IpRestrictionHandler.PRIORITY = 990

function IpRestrictionHandler:new()
  IpRestrictionHandler.super.new(self, "ip-restriction")
end

function IpRestrictionHandler:init_worker()
  IpRestrictionHandler.super.init_worker(self)
  local ok, err = iputils.enable_lrucache()
  if not ok then
    ngx.log(ngx.ERR, "[ip-restriction] Could not enable lrucache: ", err)
  end
end

function IpRestrictionHandler:access(conf)
  IpRestrictionHandler.super.access(self)
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

return IpRestrictionHandler
