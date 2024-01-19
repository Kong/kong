-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local pl_string      = require "pl.stringx"
local ee_api         = require "kong.enterprise_edition.api_helpers"
local ee_admins      = require "kong.enterprise_edition.admins_helpers"
local rbac           = require "kong.rbac"
local workspaces     = require "kong.workspaces"

local kong = kong
local log = ngx.log
local ERR = ngx.ERR

local match = string.match
local lower = string.lower
local find = string.find
local sub = string.sub
local decode_base64 = ngx.decode_base64

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

  -- delete rbac_user_roles
  local cache_key = kong.db.rbac_user_roles:cache_key(admin.rbac_user.id)
  kong.cache:invalidate(cache_key)

  for rbac_user_role, _ in kong.db.rbac_user_roles:each_for_user({ id = admin.rbac_user.id }) do
    kong.db.rbac_user_roles:delete(rbac_user_role)
  end

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

return _M
