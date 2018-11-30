local BasePlugin = require "kong.plugins.base_plugin"
local util = require "kong.tools.utils"
local access = require "kong.plugins.session.access"
local session = require "kong.plugins.session.session"

-- Grab pluginname from module name
local plugin_name = ({...})[1]:match("^kong%.plugins%.([^%.]+)")

local KongSessionHandler = BasePlugin:extend()

-- TODO: determine best priority
KongSessionHandler.PRIORITY = 1900

function KongSessionHandler:new()
  KongSessionHandler.super.new(self, plugin_name)
end

function KongSessionHandler:header_filter(conf)
  KongSessionHandler.super.header_filter(self)
  
  local session = session.open_session(conf)
  session.data.authenticated_credential = ngx.ctx.authenticated_credential
  session.data.authenticated_consumer = ngx.ctx.authenticated_consumer
  session:save()
end

function KongSessionHandler:access(conf)
  KongSessionHandler.super.access(self)
  access.execute(conf)
end


return KongSessionHandler
