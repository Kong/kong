local BasePlugin = require "kong.plugins.base_plugin"
local util = require "kong.tools.utils"
local access = require "kong.plugins.session.access"

-- Grab pluginname from module name
local plugin_name = ({...})[1]:match("^kong%.plugins%.([^%.]+)")

local KongSessionHandler = BasePlugin:extend()

-- TODO: determine best priority
KongSessionHandler.PRIORITY = 3000

function KongSessionHandler:new()
  KongSessionHandler.super.new(self, plugin_name)
end

function KongSessionHandler:access(conf)
  KongSessionHandler.super.access(self)
  access.execute(conf)
end


return KongSessionHandler
