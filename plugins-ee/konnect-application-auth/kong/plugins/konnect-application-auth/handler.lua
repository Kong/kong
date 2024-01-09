-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]
local meta = require "kong.meta"
local helpers = require "kong.enterprise_edition.consumer_groups_helpers"
local oidc_plugin = require "kong.plugins.openid-connect.handler"
local kaa_oidc = require "kong.plugins.konnect-application-auth.oidc"
local arguments = require "kong.plugins.openid-connect.arguments"
local sha256_hex = require "kong.tools.sha256".sha256_hex
local set_context = require("kong.plugins.konnect-application-auth.application_context").set_context

local tostring = tostring
local ngx = ngx
local kong = kong
local table = table
local type = type
local ipairs = ipairs
local error = error

local EMPTY = {}
local OIDC_CONFIG_STATE = {}

local KonnectApplicationAuthHandler = {
  PRIORITY = 950,
  VERSION = meta.core_version,
}

--- get_oidc_config_state returns the plugin oidc config state for the given
--- service. This is used to speed-up the lookup of what we need to parse during
--- a request
---@return table config_state the config state for the given service
local function get_oidc_config_state(service_id)
  return OIDC_CONFIG_STATE[service_id]
end

-- has_value returns a boolean if the array has the value passed in parameter
---@param tab table table to lookup into
---@param val any value to lookup into the table for
---@return boolean presence presence of the value in the given table
local function has_value(tab, val)
  for _, value in ipairs(tab) do
    if value == val then
      return true
    end
  end

  return false
end

local function get_api_key(plugin_conf)
  local apikey
  local headers = kong.request.get_headers()
  local query = kong.request.get_query()

  for i = 1, #plugin_conf.key_names do
    local name = plugin_conf.key_names[i]

    -- search in headers
    apikey = headers[name]
    if not apikey then
      -- search in querystring
      apikey = query[name]
    end

    if type(apikey) == "string" then
      query[name] = nil
      kong.service.request.set_query(query)
      kong.service.request.clear_header(name)
      break
    elseif type(apikey) == "table" then
      -- duplicate API key
      return nil, {
        status = 401,
        message = "Duplicate API key found"
      }
    end
  end

  if apikey and apikey ~= "" then
    return sha256_hex(apikey)
  end
end

local function get_identifier(plugin_conf)
  local identifier

  if plugin_conf.auth_type == "openid-connect" then
    -- get the client_id from authenticated credential
    identifier = (kong.client.get_credential() or EMPTY).id
  elseif plugin_conf.auth_type == "key-auth" then
    identifier = get_api_key(plugin_conf)

    kong.client.authenticate(nil, {
      id = tostring(identifier or "")
    })
  end

  local ctx = ngx.ctx
  ctx.auth_type = plugin_conf.auth_type

  if not identifier or identifier == "" then
    return nil, {
      status = 401,
      message = "Unauthorized"
    }
  end

  return identifier
end

-- load_application returns the DAO konnect-application
---@return table application
local function load_application(client_id)
  local application, err = kong.db.konnect_applications:select_by_client_id(client_id)
  if not application then
    return nil, err
  end

  return application
end

---@return boolean authorized is the application authorized for the given scope
local function is_authorized(application, scope)
  local scopes = application and application.scopes or {}
  local scopes_len = #scopes
  if scopes_len > 0 then
    for i = 1, #scopes do
      if scope == scopes[i] then
        return true
      end
    end
  end

  return false
end

--- map_consumer_groups makes the mapping of the consumer groups attached to the
--- application. If the consumer_group is not found in the kong instance it skips
--- the mapping.
---@param application table
local function map_consumer_groups(application)
  if #application.consumer_groups > 0 then
    local cg_to_map = {}
    for i = 1, #application.consumer_groups do
      if application.consumer_groups[i] ~= '' then
        local consumer_group = helpers.get_consumer_group(application.consumer_groups[i])
        if consumer_group then
          table.insert(cg_to_map, consumer_group)
        end
      end
    end
    if #cg_to_map > 0 then
      kong.client.set_authenticated_consumer_groups(cg_to_map)
    end
  end
end

--- get_oidc_app parses the current kong request and extract the auth context based
--- on the configuration auth_methods.
---@param plugin_config table configuration of the kaa plugin
---@return table oidc_application the oidc application in the konnect_applications DAO
local function get_oidc_app(plugin_config)
  local config_state = get_oidc_config_state(plugin_config.service_id)
  if not config_state then
    error("no config state found for service:" .. plugin_config.service_id)
  end

  -- For client credentials we get the `Authorization` header, check if the prefix
  -- is `Basic` and then base64 decode, split on `:` and extract the client ID
  -- if the client ID is found we try to find the application in the DAO
  -- If it's not found we don't return an application then it leads to 401
  if config_state.client_credentials then
    local client_id = kaa_oidc.client_credentials_get()
    if client_id then
      return load_application(client_id)
    end
  end

  -- For the bearer parsing we need to take the bearer from the request header
  -- Authorization, check if it has BEARER prefix, then parse the JWT (not verifying it)
  -- if the JWT is valid we then iterate on all the strategies that has `bearer` enabled
  -- and check the `credential_claim` array to check if we can find an application id in
  -- on of those claims
  if config_state.bearer then
    local jwt_obj = kaa_oidc.bearer_get()
    if jwt_obj and jwt_obj.valid then
      for _, oidc_conf in ipairs(plugin_config.v2_strategies.openid_connect) do
        local conf = oidc_conf.config

        if not has_value(conf.auth_methods, "bearer") then
          goto continue_bearer
        end

        for j = 1, #conf.credential_claim do
          local current_claim = conf.credential_claim[j]
          local app = load_application(jwt_obj.payload[current_claim])
          if app then
            return app
          end
        end

        ::continue_bearer::
      end
    end
  end

  if config_state.session then
    -- For session parsing we need to extract the session from the cookie using the
    -- OIDC configuration to know the session cookie location with `session_cookie_name`
    -- then instanciate the configuration of the plugin to extract the session with the
    -- proper secret
    for i = 1, #plugin_config.v2_strategies.openid_connect do
      local conf = plugin_config.v2_strategies.openid_connect[i].config
      if not has_value(conf.auth_methods, "session") then
        goto continue_session
      end

      local session_token = kaa_oidc.get_cookie(conf.session_cookie_name)

      if not session_token then
        goto continue_session
      end

      -- following needs to be refactored to shared code with openid-connect plugin
      -- @zekth @bungle
      local args = arguments(conf)
      local issuer = kaa_oidc.get_issuer(args)
      local session, _, session_present = kaa_oidc.open_session(args, issuer)

      if session_present then
        local subject = session:get_subject()
        if subject then
          return load_application(subject)
        end
      end

      ::continue_session::
    end
  end

  return nil

end

--- get_app returns the application DAO from the application identifier
--- application identifier is the client_id for an OIDC app and the hash
--- of the key for a keyauth authentication
---@param appIdentifier string identifier of the app. Can be hash of api key or openid-connect clientID
---@return table application
local function get_app(appIdentifier)
  local cache = kong.cache
  local application_cache_key = kong.db.konnect_applications:cache_key(appIdentifier)
  local application, err = cache:get(application_cache_key, nil, load_application, appIdentifier)
  if err then
    return error(err)
  end
  return application
end

--- Access phase for "v2-strategies" auth_type
---@param plugin_conf table the KAA plugin configuration
local function v2_access_phase(plugin_conf)
  -- TODO: auth code
  local appIdentifier
  local application
  local err

  if plugin_conf.v2_strategies.key_auth then
    for i = 1, #plugin_conf.v2_strategies.key_auth do
      -- get_api_key consumes the old schema definition of key-auth
      -- reusing the key_auth config from v2 that has the same schema definition
      appIdentifier = get_api_key(plugin_conf.v2_strategies.key_auth[i].config)
      if appIdentifier then

        application, err = get_app(appIdentifier)
        if err then
          return nil, err
        end

        if application then
          kong.client.authenticate(nil, {
            id = tostring(appIdentifier)
          })
          break
        else
          application = nil
        end
      end
    end
  end

  if not application and plugin_conf.v2_strategies.openid_connect then
    -- TODO: if only 1 oidc configuration passing directly to the OIDC phase with the config

    application = get_oidc_app(plugin_conf)
    if application then
      for i = 1, #plugin_conf.v2_strategies.openid_connect do
        local kaa_conf = plugin_conf.v2_strategies.openid_connect[i]

        if kaa_conf.strategy_id == application.auth_strategy_id then
          oidc_plugin.access(nil, kaa_conf.config)
          break
        end

      end

    end
  end

  if not application then
    return kong.response.error(401, "Unauthorized")
  end

  return application
end

local function apply_application_context(application)
  local app_context = application and application.application_context
  if app_context then
    set_context(app_context)

    if app_context.application_id then
      kong.service.request.set_header("X-Application-ID", app_context.application_id)
    end
    if app_context.developer_id then
      kong.service.request.set_header("X-Application-Developer-ID", app_context.developer_id)
    end
    if app_context.portal_id then
      kong.service.request.set_header("X-Application-Portal-ID", app_context.portal_id)
    end
    if app_context.organization_id then
      kong.service.request.set_header("X-Application-Org-ID", app_context.organization_id)
    end
  end
end

--- Access phase for "openid-connect" and "key-auth" auth_type
---@param plugin_conf table the KAA plugin configuration
local function kaa_access_phase(plugin_conf)
  local identifier, err = get_identifier(plugin_conf)
  if err then
    return kong.response.error(err.status, err.message)
  end

  local cache = kong.cache

  local application_cache_key = kong.db.konnect_applications:cache_key(identifier)
  local application, err = cache:get(application_cache_key, nil, load_application, identifier)
  if err then
    return error(err)
  end

  if not application and plugin_conf.auth_type == "key-auth" then
    return kong.response.error(401, "Unauthorized")
  end

  return application
end

function KonnectApplicationAuthHandler:access(plugin_conf)
  local application

  if plugin_conf.auth_type == "v2-strategies" then
    application = v2_access_phase(plugin_conf)
  else
    application = kaa_access_phase(plugin_conf)
  end

  if not is_authorized(application, plugin_conf.scope) then
    return kong.response.error(403, "You cannot consume this service")
  end

  map_consumer_groups(application)
  apply_application_context(application)

end

function KonnectApplicationAuthHandler:configure(configs)
  -- Initialize global state of the plugin to do faster lookup for OIDC
  -- clientID retrieval based on service id
  if not configs then
    OIDC_CONFIG_STATE = {}
    return
  end
  local oidc_state = {}
  for _, plugin_conf in ipairs(configs) do
    if plugin_conf.v2_strategies.openid_connect then
      local conf_state =  {
        config_size = 0 -- initialize to 0 to be able to increment the value
      }
      for _, oidc_config in ipairs(plugin_conf.v2_strategies.openid_connect) do
        local conf = oidc_config.config
        conf_state.config_size = conf_state.config_size + 1
        for _, method in ipairs(conf.auth_methods) do
          if method == "client_credentials" then
            conf_state.client_credentials = true
          elseif method == "bearer" then
            conf_state.bearer = true
          elseif method == "session" then
            conf_state.session = true
          end
        end
      end
      oidc_state[plugin_conf.service_id] = conf_state
    end
  end
  OIDC_CONFIG_STATE = oidc_state
end

return KonnectApplicationAuthHandler
