local singletons = require "kong.singletons"
local enums = require "kong.enterprise_edition.dao.enums"
local portal_crud = require "kong.portal.crud_helpers"
local workspaces = require "kong.workspaces"

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
  local matching_record
  for _, user in ipairs(rbac_users) do
    if user.name == params.username or
       user.name == params.custom_id or
       user.name == params.email then

      matches = matches + 1
      matching_record = user
    end
  end

  if matches > max_count then
    return false, { rbac_user = matching_record }
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
      matching_record = admin
    end
  end

  if matches > max_count then
    return false, { consumer = matching_record }
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


local function link_to_workspace(consumer_or_user, dao, workspace, plugin)
  -- either a consumer or an rbac_user is passed in
  -- figure out which one and initialize the other
  local consumer = consumer_or_user.consumer
  local rbac_user = consumer_or_user.rbac_user

  local map_filter
  if consumer then
    map_filter = { consumer_id = consumer.id }

  elseif rbac_user then
    map_filter = { user_id = rbac_user.id }

  else
    return nil, "'admin' must include a consumer or an rbac_user"

  end

  local maps, err = dao.consumers_rbac_users_map:run_with_ws_scope({},
                    dao.consumers_rbac_users_map.find_all, map_filter)

  if err then
    return nil, err
  end

  if not maps[1] then
    local m = consumer.id and ("consumer " .. consumer.id)
              or ("rbac_user " .. rbac_user.id)

    return nil, "no map found for " .. m
  end

  if not consumer then
    local res, err = dao.consumers:run_with_ws_scope({},
                     dao.consumers.find_all, { id = maps[1].consumer_id })

    if err then
      return nil, err
    end

    if not res[1] then
      return nil, "no consumer found with id " .. maps[1].consumer_id
    end

    consumer = res[1]
  end

  if not rbac_user then
    local res, err = dao.rbac_users:run_with_ws_scope({},
                     dao.rbac_users.find_all, { id = maps[1].user_id })

    if err then
      return nil, err
    end

    if not res[1] then
      return nil, "no rbac_user found with id " .. maps[1].user_id
    end

    rbac_user = res[1]
  end

  -- see if this admin is already in this workspace
  local ws_list, err = workspaces.find_workspaces_by_entity({
    workspace_id = workspace.id,
    entity_type = "consumers",
    entity_id = consumer.id,
  })

  if err then
    return nil, err
  end

  if ws_list and ws_list[1] then
    -- already linked, so no new link made
    return false
  end

  -- link consumer
  local _, err = workspaces.add_entity_relation("consumers", consumer, workspace)

  if err then
    return nil, err
  end

  -- link rbac_user
  local _, err = workspaces.add_entity_relation("rbac_users", rbac_user, workspace)

  if err then
    return nil, err
  end

  -- for now, an admin is a munging of consumer and rbac_user
  consumer.rbac_user = rbac_user
  return consumer
end
_M.link_to_workspace = link_to_workspace


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
