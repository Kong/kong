local singletons = require "kong.singletons"
local enums = require "kong.enterprise_edition.dao.enums"
local portal_crud = require "kong.portal.crud_helpers"
local workspaces = require "kong.workspaces"
local responses = require "kong.tools.responses"
local secrets = require "kong.enterprise_edition.consumer_reset_secret_helpers"
local ee_utils = require "kong.enterprise_edition.utils"
local utils = require "kong.tools.utils"

local emails = singletons.admin_emails

local lower = string.lower

local log = ngx.log
local ERR = ngx.ERR
local DEBUG = ngx.DEBUG
local _log_prefix = "[admins] "


local _M = {}

-- creates a user-friendly representation from a fully-instantiated admin
-- that we've fetched from the db. For reference:
-- https://www.gocomics.com/calvinandhobbes/1987/03/24
-- https://www.gocomics.com/calvinandhobbes/1987/03/28
local function transmogrify(admin)
  if not admin then return nil end

  return {
      id = admin.id,
      username = admin.username,
      custom_id = admin.custom_id,
      email = admin.email,
      status = admin.status,
      created_at = admin.created_at,
      updated_at = admin.updated_at,
    }
end
_M.transmogrify = transmogrify

local function sanitize_params(params)
  -- you can only manage admins here. don't try anything sneaky!
  -- TODO: We _could_ silently ignore type now. We had this check in the past
  -- to ensure people didn't accidentally create a consumer of the wrong type.
  -- That is impossible now (on this path, anyway).
  if params.type then
    return nil, {
      code = responses.status_codes.HTTP_BAD_REQUEST,
      body = { message = "Invalid parameter: 'type'" },
    }
  end

  -- ignore other invalid params
  local sanitized_params = {
    id = params.id,
    email = params.email,
    username = params.username,
    custom_id = params.custom_id,
    status = params.status,
  }

  if params.email then
    -- store email in lower case so we can check uniqueness
    params.email = lower(params.email)

    local ok, err = ee_utils.validate_email(params.email)
    if not ok then
      return nil, {
        code = responses.status_codes.HTTP_BAD_REQUEST,
        body = { message = "Invalid email: " .. err },
      }
    end
  end

  return sanitized_params
end


function _M.find_all()
  -- TODO: Swap compat_find_all with select_all method that Fast-Track created
  local all_admins, err = workspaces.compat_find_all("admins")

  if err then
    return nil, err
  end

  local transmogrified_admins = {}
  for i, v in ipairs(all_admins) do
    transmogrified_admins[i] = transmogrify(v)
  end

  return {
    code = responses.status_codes.HTTP_OK,
    body = {data = transmogrified_admins },
  }
end


function _M.validate(params, db, http_method)
  local all_admins, err = workspaces.compat_find_all("admins")

  if err then
    -- unable to complete validation, so no success and no validation messages
    return nil, nil, err
  end

  local matches = 0
  local consumer, rbac_user
  for _, admin in ipairs(all_admins) do
    -- if we're doing an update, don't compare us to ourself
    if http_method == "PATCH" and params.id == admin.id then
      goto continue
    end

    if admin.email and admin.email == params.email or
       admin.username and admin.username == params.username or
       admin.custom_id and admin.custom_id == params.custom_id
    then

      matches = matches + 1
    end

    -- XXX we're only looking at rbac_users associated to admins, but we
    -- need to make sure that the parameters passed will be unique across
    -- all rbac_users. TODO - figure out how to find all rbac_users in
    -- global scope.
    rbac_user, err = workspaces.run_with_ws_scope(
      {},
      db.rbac_users.select,
      db.rbac_users,
      { id = admin.rbac_user.id }
    )
    if not rbac_user then
      -- bad data: can't have an admin without an rbac_user
      return nil, nil, (err or "rbac_user not found for admin " .. admin.id)
    end
    admin.rbac_user = rbac_user

    if rbac_user.name == params.username or
       rbac_user.name == params.custom_id or
       rbac_user.name == params.email then

      matches = matches + 1
    end

    consumer, err = workspaces.run_with_ws_scope(
      {},
      db.consumers.select,
      db.consumers,
      { id = admin.consumer.id }
    )
    if not consumer then
      -- again, we should never get here: admins must have consumers
      return nil, nil, err or "consumer not found for admin " .. admin.id
    end
    admin.consumer = consumer

    if consumer.username and consumer.username == params.username then
      matches = matches + 1
    end

    if matches > 0 then
      return false, admin
    end

    ::continue::
  end

  return true
end

function _M.generate_token(admin, opts)
  -- generates another registration URL and token in case a user didn't get them
  local db = opts.db or singletons.db
  local remote_addr = opts.remote_addr or ngx.var.remote_addr

  if admin.status == enums.CONSUMERS.STATUS.INVITED and
     opts.generate_register_url and not
     opts.token_optional
  then

    local err
    admin, err = db.admins:select({ id = admin.id })
    if err or not admin then
      return nil, err
    end

    local expiry = singletons.configuration.admin_invitation_expiry
    local jwt, err = secrets.create(admin.consumer, remote_addr, expiry)
    if err then
      return nil, err
    end

    admin = transmogrify(admin)
    admin.register_url = emails:register_url(admin.email, jwt)
    admin.token = jwt
  end

  return {
    code = responses.status_codes.HTTP_OK,
    body = admin,
  }
end

function _M.create(params, opts)
  local token_optional = opts.token_optional or false

  local safe_params, validation_failures = sanitize_params(params)
  if validation_failures then
    return validation_failures
  end

  local _, admin, err = _M.validate(safe_params, opts.db, "POST")

  if err then
    return nil, err
  end

  if admin then
    -- already exists. try to link them to current workspace.
    local linked, err = _M.link_to_workspace(admin, opts.workspace)

    if err then
      return nil, err
    end

    if linked then
      -- in a POST, this isn't the greatest response code, but we
      -- haven't really created an admin, so...
      return {
        code = responses.status_codes.HTTP_OK,
        body = { admin = admin },
      }
    end

    -- if we got here, user already exists
    return {
      code = responses.status_codes.HTTP_CONFLICT,
      body = {
        message = "user already exists with same username, email, or custom_id"
      },
    }
  end

  -- and if we got here, we're good to go.
  local admin, err = singletons.db.admins:insert(params)

  if err then
    log(ERR, _log_prefix, err)

    return {
      code = responses.status_codes.HTTP_INTERNAL_SERVER_ERROR,
      body = { message = "failed to create admin" }
    }
  end

  local jwt
  if not token_optional then
    local expiry = singletons.configuration.admin_invitation_expiry

    jwt, err = secrets.create(admin, ngx.var.remote_addr, expiry)

    if err then
      return {
        code = responses.status_codes.HTTP_OK,
        body = {
          message = "User created, but failed to create invitation",
          admin = transmogrify(admin),
        }
      }
    end
  end

  if emails then
    local _, err = emails:invite({{ username = admin.username, email = admin.email }}, jwt)
    if err then
      log(ERR, _log_prefix, "error inviting user: ", admin.email)

      return {
        code = responses.status_codes.HTTP_OK,
        body = {
          message = "User created, but failed to send invitation email",
          admin = transmogrify(admin),
        },
      }
    end
  else
    log(ERR, _log_prefix, "No email configuration found.")
  end

  return {
    code = responses.status_codes.HTTP_OK,
    body = { admin = transmogrify(admin) },
  }
end


function _M.update(params, admin_to_update, opts)
  if not next(params) then
    return { code = responses.status_codes.HTTP_BAD_REQUEST, body = "empty body" }
  end

  local db = opts.db or singletons.db

  local safe_params, validation_errors = sanitize_params(params)
  if validation_errors then
    return validation_errors
  end

  local _, duplicate, err = _M.validate(safe_params, db, "PATCH")
  if err then
    return nil, err
  end

  if duplicate then
    return {
      code = responses.status_codes.HTTP_CONFLICT,
      body = "user already exists with same username, email, or custom_id"

    }
  end

  local admin, err = workspaces.run_with_ws_scope(
    {},
    db.admins.update,
    db.admins,
    { id = admin_to_update.id },
    safe_params
  )
  if err then
    return nil, err
  end

  -- update any basic-auth credential for this user. Have to find it first.
  local creds, err = db.basicauth_credentials:page_for_consumer(admin.consumer)
  if err then
    return nil, err
  end

  if creds[1] then
    local _, err = workspaces.run_with_ws_scope({},
                   db.basicauth_credentials.update,
                   db.basicauth_credentials,
                   { id = creds[1].id },
                   { username = admin.username })
    if err then
      return nil, err
    end
  end

  return { code = responses.status_codes.HTTP_OK, body = transmogrify(admin) }
end


function _M.delete(admin_to_delete, opts)
  -- we need a full admin here, not a prettified one
  local admin, err = opts.db.admins:select({ id = admin_to_delete.id })
  if err then
    return nil, err
  end

  local _, err = opts.db.admins:delete(admin)
  if err then return
    nil, err
  end

  return { code = responses.status_codes.HTTP_NO_CONTENT }
end


function _M.find_by_username_or_id(username_or_id, raw)
  if not username_or_id then
    return nil
  end

  local admin, err

  if utils.is_valid_uuid(username_or_id) then
    admin, err = kong.db.admins:select({ id = username_or_id })
    if err then
      return err
    end
  end

  if not admin then
    admin, err = kong.db.admins:select_by_username(username_or_id)
    if err then
      return nil, err
    end
  end

  -- it's convenient to find_by_username_or_id in this module, too,
  -- and use the returned rbac_user and consumer ids.
  return raw and admin or transmogrify(admin)
end


function _M.find_by_email(email)
  if not email or email == "" then
    return nil, "email is required"
  end

  local dao = singletons.dao
  local admins, err = workspaces.run_with_ws_scope({},
                      dao.consumers.find_all,
                      dao.consumers,
                      { type = enums.CONSUMERS.TYPE.ADMIN, email = email })
  if err then
    return nil, err
  end

  return admins[1]
end


function _M.link_to_workspace(admin, workspace)
  -- see if this admin is already in this workspace. Look it up by its
  -- consumer id, because admins themselves are global.
  local ws_list, err = workspaces.find_workspaces_by_entity({
    workspace_id = workspace.id,
    entity_type = "consumers",
    entity_id = admin.consumer.id,
  })

  if err then
    return nil, err
  end

  if ws_list and ws_list[1] then
    -- already linked, so no new link made
    return false
  end

  -- link consumer
  local _, err = workspaces.add_entity_relation("consumers", admin.consumer, workspace)

  if err then
    return nil, err
  end

  -- link rbac_user
  local _, err = workspaces.add_entity_relation("rbac_users", admin.rbac_user, workspace)

  if err then
    return nil, err
  end

  return true
end


function _M.workspaces_for_admin(username_or_id)
  -- we need a full admin here, not a prettified one
  local admin, err = _M.find_by_username_or_id(username_or_id, true)
  if err then
    return nil, err
  end

  if not admin then
    return { code = 404, body = { message = "not found" }}
  end

  local rows, err = workspaces.find_workspaces_by_entity({
    entity_id = admin.rbac_user.id,
    entity_type = "rbac_users",
    unique_field_name = "id",
  })

  if err then
    return nil, err
  end

  local ws_for_admin = {}
  for i, workspace in ipairs(rows) do
    local ws, err = kong.db.workspaces:select({ id = workspace.workspace_id })

    -- since we're selecting by id and we got these id's from a list of
    -- workspace entities, whatever goes wrong here indicates some kind
    -- of data corruption. bail early.
    if err or not ws then
      return nil, (err or "workspace not found: "..  workspace.name)
    end

    ws_for_admin[i] = ws
  end

  return {
    code = 200,
    body = ws_for_admin,
  }
end


function _M.reset_password(plugin, collection, consumer, new_password, secret_id)
  log(DEBUG, _log_prefix, "searching ", plugin.name, "creds for consumer ", consumer.id)
  local credentials, err = workspaces.run_with_ws_scope({},
    singletons.dao.credentials.find_all,
    singletons.dao.credentials,
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
  local ok, err = secrets.consume_secret(secret_id)
  if not ok then
    return nil, err
  end

  return true
end

return _M
