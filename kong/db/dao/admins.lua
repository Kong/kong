local utils = require "kong.tools.utils"
local enums = require "kong.enterprise_edition.dao.enums"
local rbac      = require "kong.rbac"

local log = ngx.log
local ERR = ngx.ERR
local _log_prefix = "[admins-dao] "


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

  local unique_name = admin.username .. "-" .. utils.uuid()

  -- create rbac_user
  local rbac_user, err = self.db.rbac_users:insert({
    name = unique_name,
    user_token = utils.uuid(),
    comment = "User generated on creation of Admin.",
  })

  if err then
    return nil, err
  end

  -- create consumer
  local consumer, err = self.db.consumers:insert({
    username  = admin.username,
    custom_id = admin.custom_id,
    type = enums.CONSUMERS.TYPE.ADMIN,
  })

  if err then
    rollback_on_create(self, { rbac_user = rbac_user })
    return nil, err
  end

  local admin_for_db = {
    consumer = { id = consumer.id },
    rbac_user = { id = rbac_user.id },
    email = admin.email,
    status = admin.status or enums.CONSUMERS.STATUS.INVITED,
    username = admin.username,
    custom_id = admin.custom_id,
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


function _Admins:delete(admin, options)
  local consumer_id = admin.consumer.id
  local rbac_user_id = admin.rbac_user.id

  local roles, err = rbac.get_user_roles(kong.db, admin.rbac_user)
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

  _, err = self.db.consumers:delete({ id = consumer_id })
  if err then
    return nil, err
  end

  _, err = self.db.rbac_users:delete({ id = rbac_user_id })
  if err then
    return nil, err
  end

  for _, role in ipairs(default_roles) do
    local _, err = rbac.remove_default_role_if_empty(role)
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

  return admins[1]
end


return _Admins
