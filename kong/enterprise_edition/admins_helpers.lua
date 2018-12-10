local singletons = require "kong.singletons"
local enums = require "kong.enterprise_edition.dao.enums"
local portal_crud = require "kong.portal.crud_helpers"
local workspaces = require "kong.workspaces"
local responses = require "kong.tools.responses"
local utils = require "kong.tools.utils"
local secrets = require "kong.enterprise_edition.consumer_reset_secret_helpers"
local rbac = require "kong.rbac"
local emails = singletons.admin_emails

local log = ngx.log
local ERR = ngx.ERR
local DEBUG = ngx.DEBUG
local _log_prefix = "[admins] "


local _M = {}


local function delete_rbac_user_roles(rbac_user, dao)
  local user_roles_map, err = dao.rbac_user_roles:find_all({
    user_id = rbac_user.id,
    __skip_rbac = true,
  })
  if err then
    return nil, err
  end

  for _, map in ipairs(user_roles_map) do
    local _, err = dao.rbac_user_roles:delete(map)
    if err then
      return nil, err
    end

    local role, err = dao.rbac_roles:find({ id = map.role_id })
    if err then
      return nil, err
    end

    if role.is_default then
      local _, err = rbac.remove_user_from_default_role(rbac_user, role)
      if err then
        return nil, err
      end
    end
  end

  return true
end


local function rollback_on_create(entities, dao)
  local _, err

  if entities.consumer then
    _, err = dao.consumers:delete({ id = entities.consumer.id })
    if err then
      log(ERR, _log_prefix, err)
    end

    err = workspaces.delete_entity_relation("consumers", entities.consumer)
    if err then
      log(ERR, _log_prefix, err)
    end
  end

  if entities.rbac_user then
    _, err = dao.rbac_users:delete({ id = entities.rbac_user.id })
    if err then
      log(ERR, _log_prefix, err)
    end

    err = workspaces.delete_entity_relation("rbac_users", entities.rbac_user)
    if err then
      log(ERR, _log_prefix, err)
    end

    _, err = delete_rbac_user_roles(entities.rbac_user, dao)
    if err then
      log(ERR, _log_prefix, err)
    end
  end
end


function _M.validate(params, dao, http_method)
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


function _M.create(opts)
  local params = opts.params
  local token_optional = opts.token_optional or false
  local dao = opts.dao_factory

  local admin_name = params.username or params.custom_id

  -- create rbac_user
  local rbac_user, err = dao.rbac_users:insert({
    name = admin_name,
    user_token = utils.uuid(),
    comment = "User generated on creation of Admin.",
  })

  if err then
    log(ERR, _log_prefix, err)

    return {
      code = responses.status_codes.HTTP_INTERNAL_SERVER_ERROR,
      body = { message = "failed to create admin (1)"}
    }
  end

  -- create consumer
  local consumer, err = dao.consumers:insert({
    username  = params.username,
    custom_id = params.custom_id,
    type = params.type,
    email = params.email,
    status = enums.CONSUMERS.STATUS.INVITED,
  })

  if err then
    rollback_on_create({ rbac_user = rbac_user }, dao)
    log(ERR, _log_prefix, err)

    return {
      code = responses.status_codes.HTTP_INTERNAL_SERVER_ERROR,
      body = { message = "failed to create admin (2)" }
    }
  end

  -- create mapping
  local _, err = dao.consumers_rbac_users_map:insert({
    consumer_id = consumer.id,
    user_id = rbac_user.id,
  })

  if err then
    rollback_on_create({ rbac_user = rbac_user, consumer = consumer }, dao)
    log(ERR, _log_prefix, err)

    return {
      code = responses.status_codes.HTTP_INTERNAL_SERVER_ERROR,
      body = { message = "failed to create admin (3)" }
    }
  end

  local jwt
  if not token_optional then
    local expiry = singletons.configuration.admin_invitation_expiry

    jwt, err = secrets.create(consumer, ngx.var.remote_addr, expiry)

    if err then
      return {
        code = responses.status_codes.HTTP_OK,
        body = {
          message = "User created, but failed to create invitation",
          consumer = consumer,
          rbac_user = rbac_user,
        }
      }
    end
  end

  if emails then
    local _, err = emails:invite({{ username = admin_name, email = consumer.email }}, jwt)
    if err then
      log(ERR, _log_prefix, "error inviting user: ", consumer.email)

      return {
        code = responses.status_codes.HTTP_OK,
        body = {
          message = "User created, but failed to send invitation email",
          rbac_user = rbac_user,
          consumer = consumer,
        },
      }
    end
  else
    log(ERR, _log_prefix, "No email configuration found.")
  end

  return {
    code = responses.status_codes.HTTP_OK,
    body = {
      rbac_user = rbac_user,
      consumer = consumer,
    }
  }
end


function _M.update(params, consumer, rbac_user)
  if not next(params) then
    return { code = responses.status_codes.HTTP_BAD_REQUEST, body = "empty body" }
  end

  -- update consumer
  local admin, err = singletons.dao.consumers:update(params, { id = consumer.id })
  if err then
    return nil, err
  end

  if not admin then
    return { code = responses.status_codes.HTTP_NOT_FOUND }
  end

  if consumer.username == params.username then
    -- username didn't change, nothing more to do here.
    -- return same data structure as passed in
    admin.rbac_user = rbac_user
    return { code = responses.status_codes.HTTP_OK, body = admin }
  end

  -- update rbac_user if consumer.username changed, because these have
  -- to stay in sync in order for us to authenticate this admin
  if rbac_user.name ~= admin.username then
    rbac_user, err = singletons.dao.rbac_users:update(
                     { name = admin.username },
                     { id = rbac_user.id })
    if err then
      return nil, err
    end
  end

  -- update any basic-auth credential for this user. Have to find it first.
  local creds, err = singletons.dao.basicauth_credentials:run_with_ws_scope({},
                    singletons.dao.basicauth_credentials.find_all,
                    { consumer_id = admin.id })
  if err then
    return nil, err
  end

  if creds[1] then
    local _, err = singletons.dao.basicauth_credentials:run_with_ws_scope({},
                   singletons.dao.basicauth_credentials.update,
                   { username = admin.username },
                   { id = creds[1].id })
    if err then
      return nil, err
    end
  end

  -- return the updated admin, including the updated rbac_user
  admin.rbac_user = rbac_user
  return { code = responses.status_codes.HTTP_OK, body = admin }
end


function _M.find_by_username_or_id(username_or_id)
  local dao = singletons.dao
  local admins, err = dao.consumers:run_with_ws_scope({},
                      dao.consumers.find_all,
                      { type =  enums.CONSUMERS.TYPE.ADMIN })
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


function _M.find_by_email(email)
  if not email or email == "" then
    return nil, "email is required"
  end

  local dao = singletons.dao
  local admins, err = dao.consumers:run_with_ws_scope({},
                      dao.consumers.find_all,
                      { type = enums.CONSUMERS.TYPE.ADMIN, email = email })
  if err then
    return nil, err
  end

  return admins[1]
end


function _M.link_to_workspace(consumer_or_user, dao, workspace, plugin)
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
    -- the consumer or rbac_user passed in is not an admin
    -- so nothing to link, but also not a runtime error.
    -- returning explicit nils here to express that.
    return nil, nil
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


function _M.reset_password(plugin, collection, consumer, new_password, secret_id)
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

return _M
