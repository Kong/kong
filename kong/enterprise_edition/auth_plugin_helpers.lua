-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson               = require "cjson"
local pl_string           = require "pl.stringx"
local ee_api              = require "kong.enterprise_edition.api_helpers"
local ee_admins           = require "kong.enterprise_edition.admins_helpers"
local rbac                = require "kong.rbac"
local workspaces          = require "kong.workspaces"
local jwt_decoder         = require "kong.plugins.jwt.jwt_parser"
local kong_global         = require "kong.global"
local utils               = require "kong.tools.utils"

local kong          = kong
local DEBUG         = ngx.DEBUG
local ERR           = ngx.ERR
local decode_base64 = ngx.decode_base64
local header        = ngx.header
local log           = ngx.log
local http_version  = ngx.req.http_version

local match         = string.match
local lower         = string.lower
local find          = string.find
local sub           = string.sub

local _log_prefix = "[auth_plugin_helpers] "

local _M = {}

-- exit when admin is not found in DB an auto_admin_create is false
function _M.no_admin_error()
  log(ERR, _log_prefix, "Admin not found")
  return kong.response.exit(401, { message = "Unauthorized" })
end

-- ignore_case, user_name, custom_id, create_if_not_existed, set_consumer_ctx, rbac_token_enabled
-- are optional.
function _M.validate_admin_and_attach_ctx(
  self, ignore_case, user_name, custom_id,
  create_if_not_exists, set_consumer_ctx, rbac_token_enabled
)
  local admin, err = ee_api.validate_admin(ignore_case, user_name, custom_id)

  if not admin and create_if_not_exists then
    local token_optional = true
    local default_ws = kong.default_ws

    admin, err = ee_admins.create({
      username = user_name,
      custom_id = custom_id,
      rbac_token_enabled = rbac_token_enabled,
    }, {
      token_optional = token_optional,
      workspace = { id = default_ws },
      raw = true,
    })

    -- the admin helper returns the response dto
    admin = admin.body.admin
  end

  if not admin then
    _M.no_admin_error()
  end

  if err then
    log(ERR, _log_prefix, err)
    return kong.response.exit(500, err)
  end

  if admin then
    local consumer_id = admin.consumer.id
    if (set_consumer_ctx) then
      _M.set_admin_consumer_to_ctx(admin)
    end
    ee_api.attach_consumer_and_workspaces(self, consumer_id)
    return admin
  end
end

function _M.set_admin_consumer_to_ctx(admin)
  ngx.ctx.authenticated_consumer = admin.consumer
  ngx.ctx.authenticated_credential = {
    consumer_id = admin.consumer.id
  }
end

function _M.retrieve_credentials(authorization_header_value, header_type)
  local username, password
  if authorization_header_value then
    local s, e = find(lower(authorization_header_value), "^%s*" ..
                      lower(header_type) .. "%s+")
    if s == 1 then
      local cred = sub(authorization_header_value, e + 1)
      local decoded_cred = decode_base64(cred)
      username, password = match(decoded_cred, "(.-):(.+)")
    end
  end
  return username, password
end

function _M.delete_admin_groups_or_roles(admin)
  -- delete rbac_user_groups
  local cache_key = kong.db.rbac_user_groups:cache_key(admin.rbac_user.id)
  kong.cache:invalidate(cache_key)
  for group, _ in kong.db.rbac_user_groups:each_for_user({ id = admin.rbac_user.id }) do
    kong.db.rbac_user_groups:delete(group)
  end

  -- FIXME: should delete roles from IdPs only
  -- delete rbac_user_roles
  -- local cache_key = kong.db.rbac_user_roles:cache_key(admin.rbac_user.id)
  -- kong.cache:invalidate(cache_key)

  -- for rbac_user_role, _ in kong.db.rbac_user_roles:each_for_user({ id = admin.rbac_user.id }) do
  --   kong.db.rbac_user_roles:delete(rbac_user_role)
  -- end

end

function _M.map_admin_groups_by_idp_claim(admin, claim_values)
  -- first, delete all groups and all roles of the admin
  _M.delete_admin_groups_or_roles(admin)
  --second, always insert rbac_user_groups
  for _, group_name in ipairs(claim_values or {}) do
    if group_name and (type(group_name) == "string" or type(group_name) == "number") then

      local group = kong.db.groups:select_by_name(tostring(group_name))
      if not group then
        kong.log.warn(string.format("group '%s' does not exist", group_name))
        goto continue
      end

      local _, err = kong.db.rbac_user_groups:insert({ user = admin.rbac_user, group = group })
      if err then
        kong.log.err("failed insert rbac_user_groups: user = ", admin.rbac_user.id, ", group = ", group_name,
          ", err: ", err)
      end
    end
    ::continue::
  end
end

function _M.map_admin_roles_by_idp_claim(admin, claim_values)
  local delimiter = ":"

  local roles_by_ws = {}
  local roles = {}

  -- find out all the roles from the claims and store them into the roles_by_ws
  -- table
  for _, claim_value in ipairs(claim_values) do
    if type(claim_value) == "string" then

      local claim_arr = pl_string.split(claim_value, delimiter)
      local ws_name = #claim_arr > 1 and claim_arr[1]

      local ws, err
      if ws_name then
        ws, err = workspaces.select_workspace_by_name_with_cache(ws_name)
        if not ws then
          kong.log.err("failed fetching workspace ", ws_name, ": ", err)
        end
      end

      if ws then
        table.remove(claim_arr, 1)

        if not roles_by_ws[ws.id] then
          roles_by_ws[ws.id] = {}
        end

        local role_name = pl_string.join(delimiter, claim_arr)

        table.insert(roles_by_ws[ws.id], role_name)
        table.insert(roles, role_name)
      end
    end
  end
  
  local existing_roles, _ = rbac.get_user_roles(kong.db, admin.rbac_user, ngx.null)
  -- assign roles to admin by each ws
  for ws_id, ws_roles in pairs(roles_by_ws) do
    -- Todo: rbac.set_user_role improvment.
    -- the rbac.set_user_role requires ws_id when insert new roles,
    -- but not checking ws when deleting the exist roles. So that,
    -- we always input all the user's roles here.
    local _, err_str = rbac.set_user_roles(kong.db, admin.rbac_user, ws_roles, ws_id)
    if err_str then
      ngx.log(ngx.NOTICE, err_str)
    end
  end

  -- delete roles that are not in the claim
  local check_role_exists = function(ws_id, role)
    local ws_roles = roles_by_ws[ws_id]

    if not ws_roles then
      return false
    end

    local exists = false
    for _, role_name in ipairs(ws_roles) do
      if role_name == role.name then
        exists = true
        break
      end
    end
    return exists
  end

  for i = 1, #existing_roles do
    local role = existing_roles[i]
    if not role.is_default then
      local ws_id = role.ws_id

      if not check_role_exists(ws_id, role) then
        local ok, err = kong.db.rbac_user_roles:delete({
          user = { id = admin.rbac_user.id },
          role = { id = role.id },
        })
        if not ok then
          kong.log.err("Error while deleting role: " .. err .. ".")
        end
      end
    end
  end

end

-- [[ OpenID Connect helpers (ONLY for Admin API usages with Kong Manager for now)

local ID_TOKEN_HEADER     = "id_token"
local ACCESS_TOKEN_HEADER = "access_token"
local USER_INFO_HEADER    = "user_info"

local function decode_jwt_claims_from_header(header_name)
  local jwt_encoded = ngx.req.get_headers()[header_name]
  if not jwt_encoded then
    log(DEBUG, _log_prefix, "failed to get JWT from upstream header: ", header_name)
    return nil
  end

  local jwt, err = jwt_decoder:new(jwt_encoded)
  if err then
    log(ERR, _log_prefix, "failed to decode JWT: ", err)
    return nil
  end

  return jwt and jwt.claims
end

local function decode_user_info_from_header(header_name)
  local user_info_b64_encoded = ngx.req.get_headers()[header_name]
  if not user_info_b64_encoded then
    log(DEBUG, _log_prefix, "failed to get user info from upstream header: ", header_name)
    return nil
  end

  local user_info_encoded, b64_err = ngx.decode_base64(user_info_b64_encoded)
  if b64_err then
    log(ERR, _log_prefix, "failed to base64 decode user info: ", b64_err)
    return nil
  end

  local user_info, json_err = cjson.decode(user_info_encoded)
  if json_err then
    log(ERR, _log_prefix, "failed to JSON decode user info: ", json_err)
    return nil
  end

  return user_info
end

local function respond_unauthorized()
  return kong.response.exit(401, { message = "Unauthorized" })
end

-- This function prepares the config for openid-connect plugin.
--
-- Note: the flow is mainly moved from the previous /auth route handler.
-- ONLY designed for Admin API usages with Kong Manager for now.
function _M.prepare_openid_config(plugin_config, is_auth_route)
  -- Shallow copy here to avoid changing the original config table
  local config = utils.shallow_copy(plugin_config)

  -- Clear these undocumented fields to avoid schema violations
  config.admin_claim = nil
  config.admin_by = nil
  config.admin_auto_create_rbac_token_disabled = nil
  config.admin_auto_create = nil

  -- Skip consumer lookups within the plugin (this is expected as the admin's consumer cannot be
  -- matched by exact username)
  config.consumer_optional = true

  -- Do not include any tokens in the redirect URI
  config.login_tokens = {}
  config.login_methods = { "authorization_code", "session" }

  -- For logout requests from Kong Manager
  config.logout_methods = { "GET" }         -- hardcoded to GET because neither POST nor DELETE provides CSRF protection
  config.logout_query_arg = "openid_logout" -- /auth?openid_logout=true
  config.logout_revoke = true
  config.logout_revoke_access_token = true
  config.logout_revoke_refresh_token = true
  config.refresh_tokens = true

  -- Set default scopes if not provided
  -- openid: essential for OpenID Connect
  -- email: essential for the "email" claim (because we have "email" as default for admin_claims)
  -- offline_access: essential for renewing the access token and keep the session alive
  if not config.scopes then
    config.scopes = { "openid", "email", "offline_access" } -- use openid-connect default + email + offline_access
  end

  -- Set headers to allow obtaining tokens/user info after plugin executions
  config.upstream_id_token_header = ID_TOKEN_HEADER
  config.upstream_access_token_header = ACCESS_TOKEN_HEADER
  if config.search_user_info then
    config.upstream_user_info_header = USER_INFO_HEADER
  end

  -- Route-specific

  -- Only allow authorization_code on the /auth route
  config.auth_methods = is_auth_route and { "authorization_code", "session" } or { "session" }
  -- login_action is always "upstream" because we need to do some post-execution tasks
  config.login_action = "upstream" -- using "redirect" will cause the post-execution tasks to be skipped

  return config
end

-- Post hook to be called after the openid-connect plugin's execution.
-- The flow is mainly moved from the previous /auth route handler.
-- ONLY used by Admin API's OpenID Connect authentication.
--
-- Calling this function is necessary because openid-connect plugin cannot match admin consumers
-- by their usernames due to the `_ADMIN_` suffix. (See ee:constants.ADMIN_CONSUMER_USERNAME_SUFFIX)
-- Thus, we will look up for the admin manually with applicable claims.
--
-- It does the following tasks:
-- 1. Find available JWT claims from upstream headers (id_token, access_token, user_info)
-- 2. Find admin username/custom_id with the `admin_claim` from the claims from step 1
-- 3. Validate the admin and attach it to the context
-- 4. Find roles with the `role_claim` from the claims from step 1
-- 5. Map the roles to the admin (if any)
-- 6. Find the consumer using the consumer ID from the admin
-- 7. Authenticate the consumer
--
-- @return admin, consumer, response (only errors)
function _M.handle_openid_response(self, plugin_config, is_auth_route)
  local ctx = ngx.ctx

  local admin_claim = plugin_config and plugin_config.admin_claim
  local search_user_info = plugin_config and plugin_config.search_user_info
  -- Whether to create admin automatically if not found, default: true
  local admin_auto_create = plugin_config and plugin_config.admin_auto_create
      or plugin_config.admin_auto_create == nil

  -- 1. Find available JWT claims
  -- Try with id_token first
  local claims = decode_jwt_claims_from_header(ID_TOKEN_HEADER)

  -- Try with access_token if id_token is not found
  if not (claims and claims[admin_claim]) then
    claims = decode_jwt_claims_from_header(ACCESS_TOKEN_HEADER)
  end

  -- Try with user info if applicable and tokens are not found
  if search_user_info and not (claims and claims[admin_claim]) then
    claims = decode_user_info_from_header(USER_INFO_HEADER)
  end

  -- 2. Find admin username/custom_id
  local admin_claim_value = claims and claims[admin_claim]
  if not admin_claim_value then
    log(DEBUG, _log_prefix, "cannot find the admin with claim: ", admin_claim)
    return nil, nil, respond_unauthorized()
  end

  local admin_username
  local admin_custom_id
  if plugin_config and plugin_config.admin_by == "custom_id" then
    -- Find by custom_id
    admin_custom_id = admin_claim_value
  else
    -- Default: find by username
    admin_username = admin_claim_value
  end

  -- 3. Validate the admin and attach it to the context
  local admin = _M.validate_admin_and_attach_ctx(
    self,
    plugin_config and plugin_config.by_username_ignore_case,
    admin_username,
    admin_custom_id,
    admin_auto_create,
    true,
    not (plugin_config and plugin_config.admin_auto_create_rbac_token_disabled)
  )

  -- 4. Find roles
  local role_claim = plugin_config and
      plugin_config.authenticated_groups_claim and
      plugin_config.authenticated_groups_claim[1]
  local role_claim_values = claims and claims[role_claim] or ngx.ctx.authenticated_groups
  -- TODO: Try to find the role claim value among other claims if previous claims did not match
  --       Keeping it as is for now to avoid changing the behavior

  if is_auth_route then
    -- 5. Map the roles
    if role_claim_values then
      _M.map_admin_groups_by_idp_claim(admin, role_claim_values)
      _M.map_admin_roles_by_idp_claim(admin, role_claim_values)
    elseif role_claim then
      _M.delete_admin_groups_or_roles(admin)
      -- Only report not found errors when role_claim is configured
      log(DEBUG, _log_prefix, "cannot find the role with claim: ", role_claim)
    end

    if plugin_config.login_redirect_uri then
      header["Cache-Control"] = "no-store"
      if http_version() <= 1.0 then
        header["Pragma"] = "no-cache"
      end

      return kong.response.exit(302, "", { Location = plugin_config.login_redirect_uri })
    end
  end

  if not ctx.authenticated_consumer then
    log(DEBUG, _log_prefix, "no consumer was mapped by the openid-connect plugin")
    return nil, nil, respond_unauthorized()
  end

  -- ngx.ctx.authenticated_consumer is set by previous steps.
  -- However, it is a table which only contains the consumer ID.
  -- e.g., { id = "00000000-0000-0000-0000-000000000000" }
  -- Functions like authenticate() in ee:api_helpers is expecting a full consumer object
  -- instead of a table with only the ID.

  -- 7. Authenticate the consumer
  local saved_phase = ctx.KONG_PHASE
  -- Bypass the phase assertion in kong.client.load_consumer and kong.client.authenticate
  -- See also: access handler in the session plugin
  ctx.KONG_PHASE = kong_global.phases.access

  -- 6. Find the consumer with the consumer ID from the admin
  local consumer_id = ctx.authenticated_consumer.id
  local consumer_cache_key = kong.db.consumers:cache_key(consumer_id)
  local consumer, err = kong.cache:get(consumer_cache_key, nil,
    kong.client.load_consumer, consumer_id)

  if err then
    log(ERR, _log_prefix, "failed to load the consumer with id: ", consumer_id, ", error: ", err)
    return nil, nil, respond_unauthorized()
  elseif not consumer then
    log(ERR, _log_prefix, "consumer is not found with id: ", consumer_id)
    return nil, nil, respond_unauthorized()
  end

  -- Authenticate the consumer because the openid-connect plugin didn't do this for us
  kong.client.authenticate(consumer)
  -- Restore the phase
  ctx.KONG_PHASE = saved_phase

  return admin, consumer, nil
end

-- End of OpenID Connect helpers ]]

return _M
