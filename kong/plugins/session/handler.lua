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

  if not ctx.authenticated_credential then
    -- don't open sessions for anonymous users
    return
  end

  local credential_id = ctx.authenticated_credential and ctx.authenticated_credential.id
  local consumer_id = ctx.authenticated_consumer and ctx.authenticated_consumer.id
  local s = ctx.authenticated_session

  -- if session exists and the data in the session matches the ctx then
  -- don't worry about saving the session data or sending cookie
  if s and s.present then
    if s.data and s.data.authenticated_credential == credential_id and
      s.data.authenticated_consumer == consumer_id
    then
      return
    end
  end

  -- session is no longer valid
  -- create new session and save the data / send the Set-Cookie header
  if consumer_id then
    s = s or session.open_session(conf)
    s.data.authenticated_credential = credential_id or consumer_id
    s.data.authenticated_consumer = consumer_id
    s:save()
  end
end


function KongSessionHandler:access(conf)
  KongSessionHandler.super.access(self)
  access.execute(conf)
end


return KongSessionHandler
