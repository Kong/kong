local singletons = require "kong.singletons"
local enums = require "kong.enterprise_edition.dao.enums"
local portal_crud = require "kong.portal.crud_helpers"

local log = ngx.log
local DEBUG = ngx.DEBUG
local _log_prefix = "[admins] "


local _M = {}

local function validate(params, dao, http_method)
  -- how many rows do we expect to find?
  local max_count = http_method == "POST" and 0 or 1

  -- get all rbac users
  local rbac_users, err = dao.rbac_users:run_with_ws_scope({},
      dao.rbac_users.find_all)

  if err then
    -- unable to complete validation, so no success and no validation messages
    return nil, nil, err
  end

  local matches = 0
  for _, user in ipairs(rbac_users) do
    if user.name == params.username or
       user.name == params.custom_id or
       user.name == params.email then

      matches = matches + 1
    end
  end

  if matches > max_count then
    return false, "rbac_user already exists"
  end

  -- now check admin consumers
  local admins, err = dao.consumers:run_with_ws_scope({},
      dao.consumers.find_all, { type =  enums.CONSUMERS.TYPE.ADMIN })

  if err then
    -- unable to complete validation, so no success and no validation messages
    return nil, nil, err
  end

  matches = 0
  for _, admin in ipairs(admins) do
    if (admin.custom_id and admin.custom_id == params.custom_id) or
      (admin.username and admin.username == params.username) or
      (admin.email and admin.email == params.email) then

      matches = matches + 1
    end
  end

  if matches > max_count then
    return false, "consumer already exists"
  end

  return true
end
_M.validate = validate


local function find_by_username_or_id(username_or_id)
  local dao = singletons.dao
  local admins, err = dao.consumers:run_with_ws_scope({},
    dao.consumers.find_all, { type =  enums.CONSUMERS.TYPE.ADMIN })

  if err then
    return nil, err
  end

  for _, admin in ipairs(admins) do
    if admin.id == username_or_id or
       admin.username == username_or_id then

      return admin
    end
  end
end
_M.find_by_username_or_id = find_by_username_or_id


local function reset_password(plugin, collection, consumer, new_password, secret_id)
  log(DEBUG, _log_prefix, "searching ", plugin.name, "creds for consumer ", consumer.id)
  local credentials, err = singletons.dao.credentials:run_with_ws_scope({},
    singletons.dao.credentials.find_all,
    {
      consumer_id = consumer.id,
      plugin = plugin.name,
    }
  )

  if err then
    return nil, err
  end

  local credential = credentials[1]
  if not credential then
    log(DEBUG, _log_prefix, "no credential found")
    return false
  end

  log(DEBUG, _log_prefix, "found credential")

  -- expedient use of portal_crud here
  local ok, err = portal_crud.update_login_credential(
    { [plugin.credential_key] = new_password },
    collection,
    { consumer_id = consumer.id, id = credential.id }
  )

  if err then
    return nil, err
  end

  if not ok then
    log(DEBUG, _log_prefix, "failed to update credential")
    return false
  end

  log(DEBUG, _log_prefix, "password was reset, updating secrets")
  -- Mark the token secret as consumed
  local _, err = singletons.dao.consumer_reset_secrets:update({
    status = enums.TOKENS.STATUS.CONSUMED,
    updated_at = ngx.now() * 1000,
  }, {
    id = secret_id,
  })

  if err then
    return nil, err
  end

  return true
end
_M.reset_password = reset_password

return _M
