local ee_api        = require "kong.enterprise_edition.api_helpers"
local ws_helper     = require "kong.workspaces.helper"
local constants     = require "kong.constants"
local utils         = require "kong.tools.utils"
local enums         = require "kong.enterprise_edition.dao.enums"
local ws_constants  = constants.WORKSPACE_CONFIG


local _M = {}

local auth_plugins = {
  ["basic-auth"] =     { name = "basic-auth", dao = "basicauth_credentials", credential_key = "password" },
  ["oauth2"] =         { name = "oauth2",     dao = "oauth2_credentials" },
  ["hmac-auth"] =      { name = "hmac-auth",  dao = "hmacauth_credentials" },
  ["jwt"] =            { name = "jwt",        dao = "jwt_secrets" },
  ["key-auth"] =       { name = "key-auth",   dao = "keyauth_credentials", credential_key = "key" },
  ["openid-connect"] = { name = "openid-connect" },
}


local function execute_plugin(plugin_name, dao_factory, conf_key, workspace, phases)
  local conf = ws_helper.retrieve_ws_config(conf_key, workspace)
  local prepared_plugin = ee_api.prepare_plugin(ee_api.apis.PORTAL,
                                                dao_factory, plugin_name, conf)

  for _, phase in ipairs(phases) do
    ee_api.apply_plugin(prepared_plugin, phase)
  end
end


local function get_conf_arg(conf, name, default)
  local value = conf[name]
  if value ~= nil and value ~= "" then
    if type(value) ~= "table" or next(value) then
      return value
    end
  end

  return default
end


local function check_oidc_session()
  local workspace = ws_helper.get_workspace()
  local conf = ws_helper.retrieve_ws_config(ws_constants.PORTAL_AUTH_CONF, workspace)
  conf = utils.deep_copy(conf or {})
  local cookie_name = get_conf_arg(conf, "session_cookie_name", "session")

  local vars = ngx.var
  if vars["cookie_" .. cookie_name] == nil then
    return false
  end

  return true
end


local function verify_consumer(self, dao_factory, helpers)
  self.consumer = ngx.ctx.authenticated_consumer

  -- Validate status - check if we have an approved developer type consumer
  if not self.consumer or
    self.consumer.status ~= enums.CONSUMERS.STATUS.APPROVED  or
    self.consumer.type   ~= enums.CONSUMERS.TYPE.DEVELOPER then

    if ngx.ctx.authenticated_session then
      ngx.ctx.authenticated_session:destroy()
    end

    return
  end

  self.is_authenticated = true
end


function _M.validate_auth_plugin(self, dao_factory, helpers)
  local workspace = ws_helper.get_workspace()
  local portal_auth = ws_helper.retrieve_ws_config(ws_constants.PORTAL_AUTH,
                                                                    workspace)

  self.plugin = auth_plugins[portal_auth]
  if not self.plugin then
    return helpers.responses.send_HTTP_NOT_FOUND()
  end

  self.collection = dao_factory[self.plugin.dao]
end


function _M.login(self, dao_factory, helpers)
  local status

  _M.validate_auth_plugin(self, dao_factory, helpers)
  local workspace = ws_helper.get_workspace()

  -- run the auth plugin access phase to verify creds
  execute_plugin(self.plugin.name, dao_factory,
                                   ws_constants.PORTAL_AUTH_CONF,
                                   workspace, {"access"})

  -- if not openid-connect, run session header_filter to attach session to response
  local portal_auth = ws_helper.retrieve_ws_config(ws_constants.PORTAL_AUTH,
                                                                     workspace)
  if portal_auth ~= "openid-connect" then
    -- run the session header filter to start a new session
    execute_plugin("session", dao_factory, ws_constants.PORTAL_SESSION_CONF,
                                                  workspace, {"header_filter"})
  end

  verify_consumer(self, dao_factory, helpers)

  if self.consumer then
    status = ee_api.get_consumer_status(self.consumer)
  end

  if not self.is_authenticated then
    return helpers.responses.send_HTTP_UNAUTHORIZED(status)
  end
end


function _M.authenticate_api_session(self, dao_factory, helpers)
  local status

  _M.validate_auth_plugin(self, dao_factory, helpers)
  local workspace = ws_helper.get_workspace()

  -- if openid-connect, use the plugin to verify auth
  local portal_auth = ws_helper.retrieve_ws_config(ws_constants.PORTAL_AUTH,
                                                                     workspace)
  if portal_auth == "openid-connect" then
    execute_plugin(self.plugin.name, dao_factory,
                          ws_constants.PORTAL_AUTH_CONF, workspace, {"access"})
  else
    -- otherwise, verify the session
    execute_plugin("session", dao_factory, ws_constants.PORTAL_SESSION_CONF,
                                         workspace, {"access", "header_filter"})
  end

  verify_consumer(self, dao_factory, helpers)

  if self.consumer then
    status = ee_api.get_consumer_status(self.consumer)
  end

  if not self.is_authenticated then
    return helpers.responses.send_HTTP_UNAUTHORIZED(status)
  end
end


function _M.authenticate_gui_session(self, dao_factory, helpers)
  local workspace = ws_helper.get_workspace()
  local portal_auth = ws_helper.retrieve_ws_config(ws_constants.PORTAL_AUTH,
                                                                    workspace)

  if portal_auth == nil or portal_auth == '' then
    self.is_authenticated = true
    return
  end

  _M.validate_auth_plugin(self, dao_factory, helpers)

  if portal_auth == "openid-connect" then
    -- check if user has valid session
    local has_session = check_oidc_session()

    -- assume unauthenticated if no session
    if not has_session then
      self.is_authenticated = false
      return
    end

    execute_plugin(self.plugin.name, dao_factory,
                          ws_constants.PORTAL_AUTH_CONF, workspace, {"access"})
  else
    -- otherwise, verify the session
    execute_plugin("session", dao_factory, ws_constants.PORTAL_SESSION_CONF,
                                        workspace, {"access", "header_filter"})
  end

  verify_consumer(self, dao_factory, helpers)
end


return _M
