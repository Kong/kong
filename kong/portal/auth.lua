-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local ee_api        = require "kong.enterprise_edition.api_helpers"
local workspaces    = require "kong.workspaces"
local constants     = require "kong.constants"
local utils         = require "kong.tools.utils"
local enums         = require "kong.enterprise_edition.dao.enums"
local rbac          = require "kong.rbac"
local auth_helpers  = require "kong.enterprise_edition.auth_helpers"
local file_helpers  = require "kong.portal.file_helpers"
local workspace_config = require "kong.portal.workspace_config"

local ws_constants  = constants.WORKSPACE_CONFIG

local log = ngx.log
local ERR = ngx.ERR
local decode_base64 = ngx.decode_base64
local re_gmatch = ngx.re.gmatch
local re_match = ngx.re.match

local DEVELOPER_TYPE = enums.CONSUMERS.TYPE.DEVELOPER

local UNEXPECTED_ERR = { message = "An unexpected error occurred" }
local UNAUTHED_ERR = { message = "Unauthorized" }

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

local oidc_redirect_map = {
  forbidden = {
    oidc = "forbidden_redirect_uri",
    portal_conf = "unauthorized"
  },
  login = {
    oidc = "login_redirect_uri",
    portal_conf = "login"
  }
}

local function get_oidc_auth_redirect(workspace, auth_conf, redirect_type)
  local redirect_map = oidc_redirect_map[redirect_type]
  if not redirect_map then
    return
  end

  -- first try OIDC conf for redirect
  local redirect_uri_arr = auth_conf[redirect_map.oidc]
  if type(redirect_uri_arr) == "table" then
    local client_arg = auth_conf.client_argx
    local client_idx = ngx.header[client_arg] or 1
    local oidc_redirect_uri = redirect_uri_arr[client_idx]

    if type(oidc_redirect_uri) == "string" and oidc_redirect_uri ~= "" then
      return oidc_redirect_uri
    end
  end

  -- otherwise get redirect from portal conf
  local portal_conf = file_helpers.get_conf("portal")
  local redirect_path = portal_conf and portal_conf.redirect and
                        portal_conf.redirect[redirect_map.portal_conf] or ""

  return workspace_config.build_ws_portal_gui_url(kong.configuration, workspace)  .. '/' .. redirect_path
end


local function get_oidc_developer_status()
  local workspace = workspaces.get_workspace()
  local auto_approve = workspace_config.retrieve(ws_constants.PORTAL_AUTO_APPROVE, workspace)

  if auto_approve then
    return enums.CONSUMERS.STATUS.APPROVED
  end

  return enums.CONSUMERS.STATUS.PENDING
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
  local workspace = workspaces.get_workspace()
  local conf = workspace_config.retrieve(
    ws_constants.PORTAL_AUTH_CONF,
    workspace,
    { decode_json = true }
  )
  conf = utils.cycle_aware_deep_copy(conf) or {}
  local cookie_name = get_conf_arg(conf, "session_cookie_name", "session")

  local vars = ngx.var
  if vars["cookie_" .. cookie_name] == nil then
    return false
  end

  return true
end

local function get_authenticated_developer(self)
  local consumer = ngx.ctx.authenticated_consumer
  if not consumer or consumer.type ~= DEVELOPER_TYPE then
    return nil, UNAUTHED_ERR.message
  end

  local developer, err = kong.db.developers:select_by_email(consumer.username)
  if err then
    return nil, err
  end

  if not developer then
    return nil, UNAUTHED_ERR.message
  end

  local status = developer.status

  -- normalize status if OIDC enabled and developer UNVERIFIED
  if self.plugin.name == "openid-connect" and
     status == enums.CONSUMERS.STATUS.UNVERIFIED then
    developer, err = kong.db.developers:update({ id = developer.id }, {
      status = get_oidc_developer_status()
    })

    if err then
      return nil, UNEXPECTED_ERR.message
    end

    status = developer.status
  end

  if status ~= enums.CONSUMERS.STATUS.APPROVED then
    local status_label = enums.CONSUMERS.STATUS_LABELS[developer.status]
    return nil, "Unauthorized: Developer status: " .. status_label
  end

  return developer
end


function _M.validate_auth_plugin(self, db, helpers, portal_auth)
  local workspace = workspaces.get_workspace()
  portal_auth = portal_auth or workspace_config.retrieve(
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

function _M.modify_auth_conf_cookie(session_conf, workspace)
  local portal_gui_use_subdomains = workspace_config.retrieve(
    "portal_gui_use_subdomains",
    workspace
  )

  -- when using subdomains, cookie name is safe to duplicate across workspaces
  -- because cookie will never conflict under different subdomains
  -- when using path separated workspaces, we need to set the cookie path
  -- to the workspace root path to avoid the session conflicting with other workspaces
  if not portal_gui_use_subdomains then
    local session_cookie_path = session_conf.session_cookie_path or ""
    if session_cookie_path:sub(-1) == "/" then
      session_cookie_path = session_cookie_path:sub(1, -2)
    end

    session_conf.session_cookie_path = session_cookie_path .. "/" .. workspace.name

    local authorization_cookie_path = session_conf.authorization_cookie_path or ""
    if authorization_cookie_path:sub(-1) == "/" then
      authorization_cookie_path = authorization_cookie_path:sub(1, -2)
    end

    session_conf.authorization_cookie_path = authorization_cookie_path .. "/" .. workspace.name
  end
end

-- modified from kong/plugins/basic-auth/access.lua retrieve_credentials
function _M.get_basic_auth_username()
  local username
  local authorization_header = kong.request.get_header("authorization")
  if authorization_header then
    local iterator = re_gmatch(authorization_header, "\\s*[Bb]asic\\s*(.+)")
    if not iterator then
      return nil, 'error parsing developer basic-auth header'
    end

    local m, err = iterator()
    if err then
      return nil, 'error parsing developer basic-auth header'
    end

    if m and m[1] then
      local decoded_basic = decode_base64(m[1])
      if decoded_basic then
        local basic_parts, err = re_match(decoded_basic, "([^:]+):(.*)", "oj")
        if err or not basic_parts then
          return nil, 'error parsing developer basic-auth header'
        end

        username = basic_parts[1]
      end
    end
  end

  if not username then
    return nil, 'error parsing developer basic auth-header'
  end

  return username
end


function _M.login(self, db, helpers)
  local invoke_plugin = kong.invoke_plugin
  local unauthenticated_developer

  _M.validate_auth_plugin(self, db, helpers)

  -- Login attempts are only enforced when basic-auth is enabled.
  -- We need to read the basic auth header before auth runs and the header
  -- is removed. We use username from the header to lookup up the developer
  -- so we can track login attempts below.
  local is_basic_auth = self.plugin.name == "basic-auth"
  if is_basic_auth then
    local username, err = _M.get_basic_auth_username()
    if err or not username then
      return kong.response.exit(401, UNAUTHED_ERR)
    end

    unauthenticated_developer, err = kong.db.developers:select_by_email(username)
    if err or not unauthenticated_developer then
      return kong.response.exit(401, UNAUTHED_ERR)
    end
  end

  local workspace = workspaces.get_workspace()
  local auth_conf = workspace_config.retrieve(
    ws_constants.PORTAL_AUTH_CONF,
    workspace,
    { decode_json = true }
  )

  local is_oidc = self.plugin.name == "openid-connect"
  if is_oidc then
    -- Don't exit if we don't find a consumer,
    -- we will redirect to register below if no consumer found
    auth_conf.consumer_optional = true

    -- This will allow execution beyond invoke_plugin instead of a redirection
    -- We need to check developer status after login
    auth_conf.login_action = "upstream"

    _M.modify_auth_conf_cookie(auth_conf, workspace)
  end

  local plugin_auth_response, err = invoke_plugin({
    name = self.plugin.name,
    config = auth_conf,
    phases = { "access" },
    api_type = ee_api.apis.PORTAL,
    db = db,
    exit_handler = function (res) return res end,
  })

  if err or not plugin_auth_response then
    log(ERR, err)
    return kong.response.exit(500, UNEXPECTED_ERR)
  end

  if is_basic_auth then
    local max_attempts = kong.configuration.portal_auth_login_attempts
    auth_helpers.plugin_res_handler(plugin_auth_response, unauthenticated_developer, max_attempts)
  end

  -- if not openid-connect
  -- run session header_filter to attach session to response
  if not is_oidc then
    local opts = { decode_json = true }
    local session_conf = workspace_config.retrieve(
                             ws_constants.PORTAL_SESSION_CONF, workspace, opts)
    session_conf = _M.add_required_session_conf(session_conf, workspace)

    local ok, err = invoke_plugin({
      name = "session",
      config = session_conf,
      phases = { "header_filter" },
      api_type = ee_api.apis.PORTAL,
      db = db,
    })

    if not ok then
      log(ERR, err)
      return kong.response.exit(500, UNEXPECTED_ERR)
    end
  end

  local _, err = get_authenticated_developer(self)
  if err then
    if kong.ctx.shared.authenticated_session and not is_oidc then
      kong.ctx.shared.authenticated_session:destroy()
    end

    -- oidc auth error redirects
    if is_oidc then
      local redirect
      if err == UNAUTHED_ERR.message then
        redirect = workspace_config.build_ws_portal_gui_url(kong.configuration, workspace) .. '/register'
      else
        redirect = get_oidc_auth_redirect(workspace, auth_conf, "forbidden")
      end

      if redirect then
        return ngx.redirect(redirect)
      end
    end

    return kong.response.exit(401, { message = err })
  end

  -- oidc success redirect
  if is_oidc then
    local redirect = get_oidc_auth_redirect(workspace, auth_conf, "login")
    if redirect then
      return ngx.redirect(redirect)
    end
  end
end


function _M.authenticate_api_session(self, db, helpers)
  local invoke_plugin = kong.invoke_plugin

  _M.validate_auth_plugin(self, db, helpers)

  local workspace = workspaces.get_workspace()
  local ok, err

  if self.plugin.name == "openid-connect" then
    -- if openid-connect, use the plugin to verify auth
    local auth_conf = workspace_config.retrieve(
      ws_constants.PORTAL_AUTH_CONF,
      workspace,
      { decode_json = true }
    )
    _M.modify_auth_conf_cookie(auth_conf, workspace)

    ok, err = invoke_plugin({
      name = self.plugin.name,
      config = auth_conf,
      phases = { "access" },
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
    local session_conf = workspace_config.retrieve(
                             ws_constants.PORTAL_SESSION_CONF, workspace, opts)
    session_conf = _M.add_required_session_conf(session_conf, workspace)

    ok, err = invoke_plugin({
      name = "session",
      config = session_conf,
      phases = { "access", "header_filter" },
      api_type = ee_api.apis.PORTAL,
      db = db,
    })
  end

  if not ok then
    log(ERR, err)
    return kong.response.exit(500, UNEXPECTED_ERR)
  end

  local developer, err = get_authenticated_developer(self)
  if err then
    if kong.ctx.shared.authenticated_session then
      kong.ctx.shared.authenticated_session:destroy()
    end

    return kong.response.exit(401, { message = err })
  end

  self.developer = developer
end


function _M.authenticate_gui_session(self, db, helpers)
  local invoke_plugin = kong.invoke_plugin
  local workspace = workspaces.get_workspace()
  local portal_auth = workspace_config.retrieve(ws_constants.PORTAL_AUTH,
                                                    workspace)

  if portal_auth == nil or portal_auth == '' then
    self.developer = { skip_portal_rbac = true }
    return
  end

  if self.is_admin then
    ee_api.authenticate(self,
                          kong.configuration.enforce_rbac ~= "off",
                          kong.configuration.admin_gui_auth)

    rbac.validate_user(self.rbac_user)
    self.developer = { skip_portal_rbac = true }

    return
  end

  _M.validate_auth_plugin(self, db, helpers, portal_auth)

  local ok, err
  if portal_auth == "openid-connect" then
    -- check if user has valid session
    local has_session = check_oidc_session()
    -- assume unauthenticated if no session
    -- don't exit early on /register path so we can run oidc preauth
    if not has_session and self.path ~= "/register"  then
      return
    end

    local auth_conf = workspace_config.retrieve(
      ws_constants.PORTAL_AUTH_CONF,
      workspace,
      { decode_json = true }
    )

    -- assets requests must have consumer_optional = true
    -- in order to allow people to access assets on the OIDC register page
    -- where session cookie already exists, but it's still unauthorized to perform any actions
    local assets_prefix = "/assets"
    if self.path:sub(1, #assets_prefix) == assets_prefix then
      auth_conf.consumer_optional = true
    end

    -- instruct the OIDC plugin to attach downstream_headers_claims
    if self.path == "/register" then
      auth_conf.downstream_headers_claims = auth_conf.downstream_headers_claims or {}
      auth_conf.downstream_headers_names = auth_conf.downstream_headers_names or {}
      table.insert(auth_conf.downstream_headers_claims, "email")
      table.insert(auth_conf.downstream_headers_names, "portal-registration-email")
      auth_conf.consumer_optional = true
    end

    _M.modify_auth_conf_cookie(auth_conf, workspace)

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
    local session_conf = workspace_config.retrieve(
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

  -- For register path with OIDC, process downstream claims headers
  if portal_auth == "openid-connect" and self.path == "/register" then
    local preauth_claims = {
      email = ngx.header['portal-registration-email']
    }

    -- remove the header
    ngx.header['portal-registration-email'] = nil

    -- attach to preauth_claims to be used by the render
    self.preauth_claims = preauth_claims.email and preauth_claims or nil
    return
  end

  local developer = get_authenticated_developer(self)
  if not developer then
    if kong.ctx.shared.authenticated_session then
      kong.ctx.shared.authenticated_session:destroy()
    end
    return
  end

  self.developer = developer
end


function _M.verify_developer_status(consumer)
  if consumer and consumer.type == DEVELOPER_TYPE then
    local email = consumer.username
    local developer_cache_key = kong.db.developers:cache_key(email)
    local developer, err      = kong.cache:get(developer_cache_key, nil,
                                            kong.db.developers.select_by_email,
                                            kong.db.developers, email)
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
