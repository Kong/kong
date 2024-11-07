-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local constants = require "kong.constants"
local utils     = require "kong.tools.utils"
local enums     = require "kong.enterprise_edition.dao.enums"
local rbac      = require "kong.rbac"

local tostring = tostring
local log = ngx.log
local ERR = ngx.ERR
local _log_prefix = "[admins-dao] "

local ADMIN_CONSUMER_USERNAME_SUFFIX = constants.ADMIN_CONSUMER_USERNAME_SUFFIX
local AUTH_PLUGINS                   = constants.AUTH_PLUGINS["admin"]

local function rollback_on_create(self, entities)
  local _, err

  if entities.consumer then
    _, err = self.db.consumers:delete({ id = entities.consumer.id })
    if err then
      log(ERR, _log_prefix, err)
    end
  end

  -- XXX When an rbac_user is deleted, corresponding roles should also be
  -- deleted. That's currently commented out in the rbac_user_roles schema.
  if entities.rbac_user then
    _, err = self.db.rbac_users:delete({ id = entities.rbac_user.id })
    if err then
      log(ERR, _log_prefix, err)
    end
  end
end

local handle_username_lower = function(self, entity, options)
  local err_t

  if entity.username_lower then
    err_t = self.errors:schema_violation({ username_lower = 'auto-generated field cannot be set by user' })
    return nil, tostring(err_t), err_t
  end

  if type(entity.username) == 'string' then
    entity.username_lower = entity.username:lower()
  end

  return true
end


local _Admins = {}

function _Admins:insert(admin, options)
  -- validate user-entered data before starting all these inserts.
  -- we can't do full validation (schema.validate(admin, true)) because
  -- we don't have an rbac_user and a consumer yet. But when not
  -- doing full validation, the required check only looks for
  -- ngx.null, not nil. See kong.db.schema.init:1588.
  admin.username = admin.username or ngx.null

  local ok, errors = self.schema:validate(admin, false)
  if not ok then
    local err_t = self.errors:schema_violation(errors)
    return nil, tostring(err_t), err_t
  end

  local _, err, err_t = handle_username_lower(self, admin, options)
  if err_t then
    return nil, err, err_t
  end

  local unique_name = admin.username .. "-" .. utils.uuid()

  -- create rbac_user
  local rbac_user, err = self.db.rbac_users:insert({
    name = unique_name,
    user_token = utils.uuid(),
    enabled = admin.rbac_token_enabled,
    comment = "User generated on creation of Admin.",
  }, options)

  if err then
    return nil, err
  end

  -- create consumer with admin suffix username
  local consumer, err = self.db.consumers:insert({
    username  = admin.username .. ADMIN_CONSUMER_USERNAME_SUFFIX,
    custom_id = admin.custom_id,
    type = enums.CONSUMERS.TYPE.ADMIN,
  }, options)

  if err then
    rollback_on_create(self, { rbac_user = rbac_user })
    return nil, err
  end

  if type(admin.username) == 'string' then
    admin.username_lower = admin.username:lower()
  end

  local admin_for_db = {
    consumer = { id = consumer.id },
    rbac_user = { id = rbac_user.id },
    email = admin.email,
    status = admin.status or enums.CONSUMERS.STATUS.INVITED,
    username = admin.username,
    username_lower = admin.username_lower,
    custom_id = admin.custom_id,
    rbac_token_enabled = admin.rbac_token_enabled,
  }

  -- create admin
  local saved_admin, err = self.super.insert(self, admin_for_db, options)
  if err then
    rollback_on_create(self, { rbac_user = rbac_user, consumer = consumer })
    return nil, err
  end

  -- return the fully-hydrated admin -- we're going to need these attributes
  saved_admin.consumer = consumer
  saved_admin.rbac_user = rbac_user

  return saved_admin
end

function _Admins:update(primary_key, admin, options)
  local _, err, err_t = handle_username_lower(self, admin, options)
  if err_t then
    return nil, err, err_t
  end

  return self.super.update(self, primary_key, admin, options)
end

function _Admins:update_by_username(username, admin, options)
  local _, err, err_t = handle_username_lower(self, admin, options)
  if err_t then
    return nil, err, err_t
  end

  return self.super.update_by_username(self, username, admin, options)
end

function _Admins:update_by_email(email, admin, options)
  local _, err, err_t = handle_username_lower(self, admin, options)
  if err_t then
    return nil, err, err_t
  end

  return self.super.update_by_email(self, email, admin, options)
end

function _Admins:update_by_custom_id(custom_id, admin, options)
  local _, err, err_t = handle_username_lower(self, admin, options)
  if err_t then
    return nil, err, err_t
  end

  return self.super.update_by_custom_id(self, custom_id, admin, options)
end

function _Admins:upsert(primary_key, admin, options)
  local _, err, err_t = handle_username_lower(self, admin, options)
  if err_t then
    return nil, err, err_t
  end

  return self.super.upsert(self, primary_key, admin, options)
end

function _Admins:delete(admin, options)
  local consumer_id = admin.consumer.id
  local rbac_user_id = admin.rbac_user.id

  local workspace
  if options then
    workspace = options.workspace
  end
  if not workspace then
    workspace = ngx.ctx.workspace or ngx.null
  end

  local roles, err = rbac.get_user_roles(kong.db, admin.rbac_user, workspace)
  if err then
    return nil, err
  end

  local default_roles = {}
  for _, role in ipairs(roles) do
    if role.is_default then
      default_roles[#default_roles+1] = role
    end
  end

  local _, err = self.super.delete(self, { id = admin.id }, options)
  if err then
    return nil, err
  end

  -- Delete the consumer and rbac_user by id regardless of the workspace they are in. They could be in a non-default workspace, but if the Admin
  -- has role permissions in the default super-admin workspace, they have permission to delete that consumer. 
  local delete_options = { workspace = ngx.null }
  if options ~= nil then
    for k, v in pairs(options) do
      delete_options[k] = v
    end
  end
  _, err = self.db.consumers:delete({ id = consumer_id }, delete_options)
  if err then
    return nil, err
  end

  _, err = self.db.rbac_users:delete({ id = rbac_user_id }, delete_options)
  if err then
    return nil, err
  end

  for _, role in ipairs(default_roles) do
    local _, err = rbac.remove_default_role_if_empty(role, workspace)
    if err then
      return nil, err
    end
  end

  return true
end


function _Admins:select_by_rbac_user(rbac_user)
  local admins, err = kong.db.admins:page_for_rbac_user({
    id = rbac_user.id
  })

  if err then
    return nil, err
  end

  if admins[1] then
    admins[1].rbac_token_enabled = rbac_user.rbac_token_enabled
  end

  return admins[1]
end

function _Admins:select_by_username_ignore_case(username)
  local admins, err = self.strategy:select_by_username_ignore_case(username)

  if err then
    return nil, err
  end

  -- sort by created_at date so that the first entry is the oldest
  table.sort(admins, function(a,b)
    return a.created_at < b.created_at
  end)

  return self:rows_to_entities(admins), nil
end

local function retrieve_credential(dao, consumer)
  -- retrieve credentials
  local credentials = kong.db[dao]:page_for_consumer(consumer, nil, nil, { workspace = ngx.null })
  local credential = credentials and credentials[1]
  if credential then
    return { name = dao, id = credential.id }
  end

  return nil
end

function _Admins:update_workspaces(admin, default_role, workspace)
  local gui_auth = kong.configuration.admin_gui_auth
  local auth_plugin = AUTH_PLUGINS[gui_auth]
  local credential

  if auth_plugin and (gui_auth == "basic-auth" or gui_auth == "key-auth") then
    credential = retrieve_credential(auth_plugin.dao, admin.consumer)
  end

  return self.strategy:update_workspaces(admin, default_role, workspace, credential)
end
return _Admins
