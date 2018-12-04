local BasePlugin = require "kong.plugins.base_plugin"
local access = require "kong.plugins.session.access"
local session = require "kong.plugins.session.session"


-- Grab pluginname from module name
local plugin_name = ({...})[1]:match("^kong%.plugins%.([^%.]+)")

local KongSessionHandler = BasePlugin:extend()

KongSessionHandler.PRIORITY = 1900

function KongSessionHandler:new()
  KongSessionHandler.super.new(self, plugin_name)
end

function KongSessionHandler:header_filter(conf)
  KongSessionHandler.super.header_filter(self)
  local ctx = ngx.ctx

  local credential_id = ctx.authenticated_credential and ctx.authenticated_credential.id
  local consumer_id = ctx.authenticated_consumer and ctx.authenticated_consumer.id

  -- save the session if we find ctx.authenticated_ variables
  if consumer_id then
    if not credential_id then
      credential_id = consumer_id
    end

    local s = session.open_session(conf)
    s.data.authenticated_credential = credential_id
    s.data.authenticated_consumer = consumer_id
    s:save()
  end
end


function KongSessionHandler:access(conf)
  KongSessionHandler.super.access(self)
  access.execute(conf)
end


return KongSessionHandler
