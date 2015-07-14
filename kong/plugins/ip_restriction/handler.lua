local BasePlugin = require "kong.plugins.base_plugin"
local init_worker = require "kong.plugins.ip_restriction.init_worker"
local access = require "kong.plugins.ip_restriction.access"

local IpRestrictionHandler = BasePlugin:extend()

function IpRestrictionHandler:new()
  IpRestrictionHandler.super.new(self, "ip_restriction")
end

function IpRestrictionHandler:init_worker()
  IpRestrictionHandler.super.init_worker(self)
  init_worker.execute()
end

function IpRestrictionHandler:access(conf)
  IpRestrictionHandler.super.access(self)
  access.execute(conf)
end

IpRestrictionHandler.PRIORITY = 990

return IpRestrictionHandler
