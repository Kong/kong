local BasePlugin = require "kong.plugins.base_plugin"
local access = require "kong.plugins.acl.access"

local ACLHandler = BasePlugin:extend()

function ACLHandler:new()
  ACLHandler.super.new(self, "acl")
end

function ACLHandler:access(conf)
  ACLHandler.super.access(self)
  access.execute(conf)
end

ACLHandler.PRIORITY = 950

return ACLHandler
