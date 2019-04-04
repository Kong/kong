local ee_api        = require "kong.enterprise_edition.api_helpers"
local ws_helper     = require "kong.workspaces.helper"
local constants     = require "kong.constants"
local utils         = require "kong.tools.utils"
local enums         = require "kong.enterprise_edition.dao.enums"
local singletons    = require "kong.singletons"
local ws_constants  = constants.WORKSPACE_CONFIG

local log = ngx.log
local ERR = ngx.ERR

local DEVELOPER_TYPE = enums.CONSUMERS.TYPE.DEVELOPER

local _M = {}

local auth_plugins = {
  ["basic-auth"] =     { name = "basic-auth", dao = "basicauth_credentials", credential_key = "password" },
  ["oauth2"] =         { name = "oauth2",     dao = "oauth2_credentials" },
  ["hmac-auth"] =      { name = "hmac-auth",  dao = "hmacauth_credentials" },
  ["jwt"] =            { name = "jwt",        dao = "jwt_secrets" },
  ["key-auth"] =       { name = "key-auth",   dao = "keyauth_credentials", credential_key = "key" },
  ["openid-connect"] = { name = "openid-connect" },
}

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

local function get_developer()
  local consumer = ngx.ctx.authenticated_consumer
  if not consumer or consumer.type ~= DEVELOPER_TYPE then
    return nil, "Invalid Consumer"
  end

  local developer, err = singletons.db.developers:select_by_email(consumer.username)
  if err then
    return nil, err
  end

  if not developer then
    return nil, "Developer not found"
  end

  local status = developer.status
  if status ~= enums.CONSUMERS.STATUS.APPROVED then
    return nil, "Unauthorized: Developer status: " .. enums.CONSUMERS.STATUS_LABELS[developer.status]
  end

  return developer
end


function _M.validate_auth_plugin(self, db, helpers, portal_auth)
  local workspace = ws_helper.get_workspace()
  portal_auth = portal_auth or ws_helper.retrieve_ws_config(
                                          ws_constants.PORTAL_AUTH, workspace)

  self.plugin = auth_plugins[portal_auth]
  if not self.plugin then
    return helpers.responses.send_HTTP_NOT_FOUND()
  end

  self.collection = db.daos[self.plugin.dao]

  return self.collection
end


function _M.login(self, db, helpers)
  local invoke_plugin = singletons.invoke_plugin

  _M.validate_auth_plugin(self, db, helpers)

  local workspace = ws_helper.get_workspace()
  local auth_conf = ws_helper.retrieve_ws_config(ws_constants.PORTAL_AUTH_CONF, workspace)

  local ok, err = invoke_plugin({
    name = self.plugin.name,
    config = auth_conf,
    phases = { "access"},
    api_type = ee_api.apis.PORTAL,
    db = db,
  })

  if not ok then
    log(ERR, err)
    return helpers.responses.send_HTTP_INTERNAL_SERVER_ERROR()
  end

  -- if not openid-connect, run session header_filter to attach session to response
  if self.plugin.name ~= "openid-connect" then
    local session_conf = ws_helper.retrieve_ws_config(ws_constants.PORTAL_SESSION_CONF, workspace)
    local ok, err = invoke_plugin({
      name = "session",
      config = session_conf,
      phases = { "header_filter"},
      api_type = ee_api.apis.PORTAL,
      db = db,
    })

    if not ok then
      log(ERR, err)
      return helpers.responses.send_HTTP_INTERNAL_SERVER_ERROR()
    end
  end

  local developer, err = get_developer()
  if err then
    if ngx.ctx.authenticated_session then
      ngx.ctx.authenticated_session:destroy()
    end

    return helpers.responses.send_HTTP_UNAUTHORIZED(err)
  end

  self.developer = developer
end


function _M.authenticate_api_session(self, db, helpers)
  local invoke_plugin = singletons.invoke_plugin

  _M.validate_auth_plugin(self, db, helpers)

  local workspace = ws_helper.get_workspace()
  local ok, err

  if self.plugin.name == "openid-connect" then
    -- if openid-connect, use the plugin to verify auth
    local auth_conf = ws_helper.retrieve_ws_config(ws_constants.PORTAL_AUTH_CONF, workspace)
    ok, err = invoke_plugin({
      name = self.plugin.name,
      config = auth_conf,
      phases = { "access"},
      api_type = ee_api.apis.PORTAL,
      db = db,
    })

    if not ok then
      log(ERR, err)
      return helpers.responses.send_HTTP_INTERNAL_SERVER_ERROR()
    end
  else
    -- otherwise, verify the session
    local session_conf = ws_helper.retrieve_ws_config(ws_constants.PORTAL_SESSION_CONF, workspace)
    ok, err = invoke_plugin({
      name = "session",
      config = session_conf,
      phases = { "access", "header_filter"},
      api_type = ee_api.apis.PORTAL,
      db = db,
    })
  end

  if not ok then
    log(ERR, err)
    return helpers.responses.send_HTTP_INTERNAL_SERVER_ERROR()
  end

  local developer, err = get_developer()
  if err then
    if ngx.ctx.authenticated_session then
      ngx.ctx.authenticated_session:destroy()
    end

    return helpers.responses.send_HTTP_UNAUTHORIZED(err)
  end

  self.developer = developer
end


function _M.authenticate_gui_session(self, db, helpers)
  local invoke_plugin = singletons.invoke_plugin
  local workspace = ws_helper.get_workspace()
  local portal_auth = ws_helper.retrieve_ws_config(ws_constants.PORTAL_AUTH, workspace)

  if portal_auth == nil or portal_auth == '' then
    return
  end

  _M.validate_auth_plugin(self, db, helpers, portal_auth)

  local ok, err
  if portal_auth == "openid-connect" then
    -- check if user has valid session
    local has_session = check_oidc_session()
    
    -- assume unauthenticated if no session
    if not has_session then
      return
    end

    local auth_conf = ws_helper.retrieve_ws_config(ws_constants.PORTAL_AUTH_CONF, workspace)
    ok, err = invoke_plugin({
      name = self.plugin.name,
      config = auth_conf,
      phases = { "access" },
      api_type = ee_api.apis.PORTAL,
      db = db,
    })
  else
    -- otherwise, verify the session
    local session_conf = ws_helper.retrieve_ws_config(ws_constants.PORTAL_SESSION_CONF, workspace)
    ok, err = invoke_plugin({
      name = "session",
      config = session_conf,
      phases = { "access", "header_filter"},
      api_type = ee_api.apis.PORTAL,
      db = db,
    })
  end

  if not ok then
    log(ERR, err)
    return helpers.responses.send_HTTP_INTERNAL_SERVER_ERROR()
  end

  local developer = get_developer()
  if not developer then
    if ngx.ctx.authenticated_session then
      ngx.ctx.authenticated_session:destroy()
    end
    return
  end

  self.developer = developer
end


function _M.verify_developer_status(consumer)
  if consumer and consumer.type == DEVELOPER_TYPE then
    local email = consumer.username
    local developer, err = singletons.db.developers:select_by_email(email)

    if err then
      kong.log.err(err)
      return false
    end

    local status = developer.status
    if status ~= enums.CONSUMERS.STATUS.APPROVED then
      return false, 'Unauthorized: Developer status ' .. '"' .. enums.CONSUMERS.STATUS_LABELS[developer.status] .. '"'
    end
  end

  return true
end


return _M
