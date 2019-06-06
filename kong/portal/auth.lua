local ee_api        = require "kong.enterprise_edition.api_helpers"
local workspaces    = require "kong.workspaces"
local constants     = require "kong.constants"
local utils         = require "kong.tools.utils"
local enums         = require "kong.enterprise_edition.dao.enums"
local singletons    = require "kong.singletons"
local rbac          = require "kong.rbac"

local ws_constants  = constants.WORKSPACE_CONFIG

local log = ngx.log
local ERR = ngx.ERR

local DEVELOPER_TYPE = enums.CONSUMERS.TYPE.DEVELOPER

local UNEXPECTED_ERR = { message = "An unexpected error occurred" }

local kong = kong

local _M = {}

local auth_plugins = {
  ["basic-auth"] = {
    name = "basic-auth",
    dao = "basicauth_credentials",
    credential_key = "password",
  },
  ["oauth2"] = {
     name = "oauth2",
     dao = "oauth2_credentials",
  },
  ["hmac-auth"] = {
    name = "hmac-auth",
    dao = "hmacauth_credentials"
  },
  ["jwt"] = {
    name = "jwt",
    dao = "jwt_secrets"
  },
  ["key-auth"] = {
    name = "key-auth",
    dao = "keyauth_credentials",
    credential_key = "key"
  },
  ["openid-connect"] = {
    name = "openid-connect"
  },
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
  local workspace = workspaces.get_workspace()
  local conf = workspaces.retrieve_ws_config(
                                      ws_constants.PORTAL_AUTH_CONF, workspace)
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
    return nil, "Unauthorized"
  end

  local developer, err = kong.db.developers:select_by_email(consumer.username)
  if err then
    return nil, err
  end

  if not developer then
    return nil, "Developer not found"
  end

  local status = developer.status
  if status ~= enums.CONSUMERS.STATUS.APPROVED then
    local status_label = enums.CONSUMERS.STATUS_LABELS[developer.status]
    return nil, "Unauthorized: Developer status: " .. status_label
  end

  return developer
end


function _M.validate_auth_plugin(self, db, helpers, portal_auth)
  local workspace = workspaces.get_workspace()
  portal_auth = portal_auth or workspaces.retrieve_ws_config(
                                          ws_constants.PORTAL_AUTH, workspace)

  self.plugin = auth_plugins[portal_auth]
  if not self.plugin then
    return kong.response.exit(404, { message = "Not found"})
  end

  self.collection = db.daos[self.plugin.dao]

  return self.collection
end


function _M.add_required_session_conf(session_conf, workspace)
  local session_cookie_name = session_conf.cookie_name
  local kong_conf_session = kong.configuration.portal_session_conf or {}

  local conflicts_with_default = workspace.name ~= "default" and
                           session_cookie_name == kong_conf_session.cookie_name

  local not_set = session_cookie_name == nil or
                  session_cookie_name == "" or
                  type(session_cookie_name) ~= "string"

  -- assign a unique cookie name if it conflicts the default or is not set
  if conflicts_with_default or not_set then
    session_conf.cookie_name = workspace.name .. "_portal_session"
  end

  session_conf.storage = "kong"

  return session_conf
end


function _M.login(self, db, helpers)
  local invoke_plugin = singletons.invoke_plugin

  _M.validate_auth_plugin(self, db, helpers)

  local workspace = workspaces.get_workspace()
  local auth_conf = workspaces.retrieve_ws_config(
                                      ws_constants.PORTAL_AUTH_CONF, workspace)

  local ok, err = invoke_plugin({
    name = self.plugin.name,
    config = auth_conf,
    phases = { "access"},
    api_type = ee_api.apis.PORTAL,
    db = db,
  })

  if not ok then
    log(ERR, err)
    return kong.response.exit(500, UNEXPECTED_ERR)
  end

  -- if not openid-connect
  -- run session header_filter to attach session to response
  if self.plugin.name ~= "openid-connect" then
    local opts = { decode_json = true }
    local session_conf = workspaces.retrieve_ws_config(
                             ws_constants.PORTAL_SESSION_CONF, workspace, opts)
    session_conf = _M.add_required_session_conf(session_conf, workspace)

    local ok, err = invoke_plugin({
      name = "session",
      config = session_conf,
      phases = { "header_filter"},
      api_type = ee_api.apis.PORTAL,
      db = db,
    })

    if not ok then
      log(ERR, err)
      return kong.response.exit(500, UNEXPECTED_ERR)
    end
  end

  local developer, err = get_developer()
  if err then
    if ngx.ctx.authenticated_session then
      ngx.ctx.authenticated_session:destroy()
    end

    return kong.response.exit(401, { message = err })
  end

  self.developer = developer
end


function _M.authenticate_api_session(self, db, helpers)
  local invoke_plugin = singletons.invoke_plugin

  _M.validate_auth_plugin(self, db, helpers)

  local workspace = workspaces.get_workspace()
  local ok, err

  if self.plugin.name == "openid-connect" then
    -- if openid-connect, use the plugin to verify auth
    local auth_conf = workspaces.retrieve_ws_config(
                                      ws_constants.PORTAL_AUTH_CONF, workspace)
    ok, err = invoke_plugin({
      name = self.plugin.name,
      config = auth_conf,
      phases = { "access"},
      api_type = ee_api.apis.PORTAL,
      db = db,
    })

    if not ok then
      log(ERR, err)
      return kong.response.exit(500, UNEXPECTED_ERR)
    end
  else
    -- otherwise, verify the session
    local opts = { decode_json = true }
    local session_conf = workspaces.retrieve_ws_config(
                             ws_constants.PORTAL_SESSION_CONF, workspace, opts)
    session_conf = _M.add_required_session_conf(session_conf, workspace)

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
    return kong.response.exit(500, UNEXPECTED_ERR)
  end

  local developer, err = get_developer()
  if err then
    if ngx.ctx.authenticated_session then
      ngx.ctx.authenticated_session:destroy()
    end

    return kong.response.exit(401, { message = err })
  end

  self.developer = developer
end


function _M.authenticate_gui_session(self, db, helpers)
  local invoke_plugin = singletons.invoke_plugin
  local workspace = workspaces.get_workspace()
  local portal_auth = workspaces.retrieve_ws_config(ws_constants.PORTAL_AUTH,
                                                    workspace)

  if portal_auth == nil or portal_auth == '' then
    self.developer = {}
    return
  end

  if self.is_admin then
    ee_api.authenticate(self,
                          kong.configuration.enforce_rbac ~= "off",
                          kong.configuration.admin_gui_auth)

    rbac.validate_user(self.rbac_user)
    self.developer = {}

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

    local auth_conf = workspaces.retrieve_ws_config(
                                      ws_constants.PORTAL_AUTH_CONF, workspace)
    ok, err = invoke_plugin({
      name = self.plugin.name,
      config = auth_conf,
      phases = { "access" },
      api_type = ee_api.apis.PORTAL,
      db = db,
    })
  else
    -- otherwise, verify the session
    local opts = { decode_json = true }
    local session_conf = workspaces.retrieve_ws_config(
                            ws_constants.PORTAL_SESSION_CONF, workspace, opts)
    session_conf = _M.add_required_session_conf(session_conf, workspace)

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
    return kong.response.exit(500, UNEXPECTED_ERR)
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
    local developer, err = kong.db.developers:select_by_email(email)

    if err then
      kong.log.err(err)
      return false
    end

    local status = developer.status
    if status ~= enums.CONSUMERS.STATUS.APPROVED then
      local label = enums.CONSUMERS.STATUS_LABELS[developer.status]
      local msg = 'Unauthorized: Developer status ' .. '"' .. label .. '"'
      return false, msg
    end
  end

  return true
end


return _M
