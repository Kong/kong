-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local constants  = require "kong.constants"
local enums = require "kong.enterprise_edition.dao.enums"
local secrets = require "kong.enterprise_edition.consumer_reset_secret_helpers"
local ee_utils = require "kong.enterprise_edition.utils"
local utils = require "kong.tools.utils"
local cjson = require "cjson"
local rbac = require "kong.rbac"
local auth_helpers = require "kong.enterprise_edition.auth_helpers"
local Errors = require "kong.db.errors"
local workspaces   = require "kong.workspaces"
local counters     = require "kong.workspaces.counters"
local tablex    = require("pl.tablex")

local emails = kong.admin_emails

local lower = string.lower

local null = ngx.null
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
    rbac_token_enabled = admin.rbac_token_enabled,
    belong_workspace = admin.belong_workspace,
    groups = admin.groups,
    workspaces = admin.workspaces,
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
      code = 400,
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
    rbac_token_enabled = params.rbac_token_enabled,
  }

  if params.email and type(params.email) == "string" then
    -- store email in lower case so we can check uniqueness
    params.email = lower(params.email)

    local ok, err = ee_utils.validate_email(params.email)
    if not ok then
      return nil, {
        code = 400,
        body = { message = "Invalid email: " .. err },
      }
    end
  end

  return sanitized_params
end

local function retrieve_default_role(rbac_user)
  local roles = rbac.get_user_roles(kong.db, rbac_user, ngx.null)
  local default_role
  for _, role in ipairs(roles or {}) do
    if role.is_default then
      default_role = role
      break
    end
  end

  return default_role
end

function _M.find_all(all_workspaces)
-- XXXCORE TODO
  local all_admins = {}
  for admin, err in kong.db.admins:each() do
    if err then
      return nil, nil, err
    end

    table.insert(all_admins, admin)
  end

  local ws_admins = {}
  setmetatable(ws_admins, cjson.empty_array_mt)
  for _, v in ipairs(all_admins) do
    local rbac_user = kong.db.rbac_users:select(v.rbac_user, { workspace = null, show_ws_id = true })
    v.belong_workspace = workspaces.select_workspace_by_id_with_cache(rbac_user.ws_id)

    if all_workspaces or v.belong_workspace.id == ngx.ctx.workspace then
      v.workspaces = rbac.find_all_ws_for_rbac_user(rbac_user, null, true)

      v.workspaces = tablex.map(function(w)
        return { name = w.name, id = w.id, is_admin_workspace = w.is_admin_workspace }
      end, v.workspaces)

      ws_admins[#ws_admins + 1] = transmogrify(v)
    end
  end

  return {
    code = 200,
    body = {
      data = ws_admins,
      next = null,
    },
  }
end


function _M.validate(params, db, admin_to_update)
  local all_admins = {}
  for admin, err in kong.db.admins:each(nil, { show_ws_id = true }) do
    if err then
      return nil, nil, err
    end

    table.insert(all_admins, admin)
  end

  local matches = 0
  local consumer, rbac_user, err
  for _, admin in ipairs(all_admins) do
    -- if we're doing an update, don't compare us to ourself
    if admin_to_update and admin_to_update.id == admin.id then
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
    rbac_user, err = kong.db.rbac_users:select({ id = admin.rbac_user.id }, { workspace = null, show_ws_id = true })
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

    consumer, err = db.consumers:select({ id = admin.consumer.id }, { workspace = null, show_ws_id = true })
    if not consumer then
      -- again, we should never get here: admins must have consumers
      return nil, nil, err or "consumer not found for admin " .. admin.id
    end
    admin.consumer = consumer

    if consumer.username and consumer.username == params.username or
       consumer.custom_id and consumer.custom_id == params.custom_id
    then
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
  local remote_addr = opts.remote_addr or ngx.var.remote_addr

  local admin_to_return = transmogrify(admin)

  if admin.status == enums.CONSUMERS.STATUS.INVITED and
     opts.generate_register_url and not
     opts.token_optional
  then

    local expiry = kong.configuration.admin_invitation_expiry
    local jwt, err = secrets.create(admin.consumer, remote_addr, expiry)
    if err then
      return nil, err
    end

    admin_to_return.register_url = emails:register_url(admin.email, jwt, admin.username)
    admin_to_return.token = jwt
  end

  return {
    code = 200,
    body = admin_to_return,
  }
end

function _M.create(params, opts)
  local token_optional = opts.token_optional or false

  local safe_params, validation_failures = sanitize_params(params)
  if validation_failures then
    return validation_failures
  end

  local db = opts.db or kong.db

  local _, admin, err = _M.validate(safe_params, db)

  if err then
    return nil, err
  end

  if admin then
    -- if we got here, user already exists
    return {
      code = 409,
      body = {
        message = "user already exists with same username, email, or custom_id"
      },
    }
  end

  -- and if we got here, we're good to go.
  local admin, err, err_t = db.admins:insert(params)

  -- error table is kong-generated schema violations
  if err_t then
    return {
      code = 400,
      body = err_t,
    }
  end

  -- unique violation error from conflicting consumer when openid-connect + by_username_ignore_case
  if err and err.code == Errors.codes.UNIQUE_VIOLATION then
    return {
      code = 409,
      body = {
        message = "user already exists with same username, email, or custom_id"
      },
    }
  end

  -- if no schema violation errors, no user friendly message
  if err then
    log(ERR, _log_prefix, err)

    return {
      code = 500,
      body = { message = "failed to create admin" }
    }
  end

  local jwt
  if not token_optional then
    local expiry = opts.token_expiry or kong.configuration.admin_invitation_expiry

    jwt, err = secrets.create(admin.consumer, opts.remote_addr, expiry)

    if err then
      return {
        code = 200,
        body = {
          message = "User created, but failed to create invitation",
          admin = opts.raw and admin or transmogrify(admin),
        }
      }
    end
  end

  if emails then
    local _, err = emails:invite({{ username = admin.username, email = admin.email }}, jwt)
    if err then
      local message = type(err.message) == "string" and err.message or ""
      log(ERR, _log_prefix, "error inviting user: ", admin.email, " ", message)

      return {
        code = 200,
        body = {
          message = "User created, but failed to send invitation email",
          admin = opts.raw and admin or transmogrify(admin),
        },
      }
    end
  else
    log(DEBUG, _log_prefix, "Kong is not configured to send email")
  end

  return {
    code = 200,
    body = { admin = opts.raw and admin or transmogrify(admin) },
  }
end


function _M.update(params, admin_to_update, opts)
  if not next(params) then
    return { code = 400, body = "empty body" }
  end

  local db = opts.db or kong.db

  local safe_params, validation_errors = sanitize_params(params)
  if validation_errors then
    return validation_errors
  end

  local _, duplicate, err = _M.validate(safe_params, db, admin_to_update)
  if err then
    return nil, err
  end

  if duplicate then
    return {
      code = 409,
      body = "user already exists with same username, email, or custom_id"
    }
  end

  local admin, err = db.admins:update(
    { id = admin_to_update.id },
    safe_params, { workspace = null })
  if err then
    -- schema violation? don't 500
    local i, _ = err:find("schema violation")
    if i then
      return {
        code = 400,
        body = { message = err:sub(i, #err) },
      }
    end

    return nil, err
  end

  -- keep consumer and credential names in sync with admin
  if params.username ~= admin_to_update.username or
    params.custom_id and params.custom_id ~= admin_to_update.custom_id
  then
    local consumer, err = db.consumers:select({id = admin.consumer.id}, {
      workspace = null, show_ws_id = true
    })
    if err then
      return nil, err
    end
    -- update consumer
    local _, err = db.consumers:update(
    { id = admin_to_update.consumer.id },
    {
      username = admin.username .. constants.ADMIN_CONSUMER_USERNAME_SUFFIX,
      custom_id = admin.custom_id,
    }, { workspace = consumer.ws_id })
    if err then
      return nil, err
    end

    -- if name changed, update basic-auth credential, if any
    if params.username ~= admin_to_update.username then
      local creds, err = db.basicauth_credentials:page_for_consumer(
        admin.consumer, nil, nil, { workspaces = null, show_ws_id = true }
      )
      if err then
        return nil, err
      end

      if creds[1] then
        local _, err = db.basicauth_credentials:update(
          { id = creds[1].id },
          { username = admin.username }, { workspace = creds[1].ws_id })
        if err then
          return nil, err
        end
      end
    end
  end

  -- keep rbac_user in sync
  if params.rbac_token_enabled ~= nil then
    -- required to get rbac_user workspace before calling :update
    local rbac_user, err = db.rbac_users:select({id = admin.rbac_user.id}, {
      workspace = null, show_ws_id = true
    })
    if err then
      return nil, err
    end
    local _, err = db.rbac_users:update(
      { id = admin_to_update.rbac_user.id },
      {
        enabled = params.rbac_token_enabled,
      }, { workspace =  rbac_user.ws_id })
    if err then
      return nil, err
    end
  end

  return { code = 200, body = transmogrify(admin) }
end

local function do_update_password(admin, params)
  local creds, bad_req_message, err = auth_helpers.verify_password(admin, params.old_password,
                                                      params.password)
  if err then
    kong.log.err("failed verify password:", err)

    return { code = 500, body = { message = "An unexpected error occurred" } }
  end

  if bad_req_message then
    return { code = 400, body = { message = bad_req_message } }
  end

  local ws_id = admin.rbac_user.ws_id
  
  if ws_id == nil then
    local consumer, err = kong.db.consumers:select(admin.consumer,
                          { show_ws_id = true, workspace = null })

    if not consumer then
      kong.log.err("failed select consumer:", err)

      return { code = 500, body = { message = "An unexpected error occurred" } }
    end

    ws_id = consumer.ws_id
  end

  local _, err = kong.db.basicauth_credentials:update(
    { id = creds.id },
    {
      consumer = { id = admin.consumer.id },
      password = params.password,
    }, { workspace = ws_id })

  if err then
    kong.log.err("failed update basicauth_credentials:", err)

    return { code = 500, body = { message = "An unexpected error occurred" } }
  end

  -- invalidate auth credential cache
  -- could be removed after we migrates/creates consumer's ws_id to default ws id
  local cache_key = kong.db.basicauth_credentials:cache_key(admin.username, nil, nil, nil, nil, ws_id)
  kong.cache:invalidate(cache_key)

  return { code = 200, body = { message = "Password reset successfully" } }
end

function _M.update_password(admin, params)
  local helpers = auth_helpers.new({ attempt_type = "change_password" })
  local attempt = helpers:retrieve_login_attempts(admin)

  if helpers:is_exceed_max_attempts(attempt) then
    kong.log.warn("exceeded the maximum number of failed password attempts for admin.")
    return { code = 400, body = { message = "Exceeded the maximum number of failed password attempts" } }
  end

  local res = do_update_password(admin, params)

  if res and res.code ~= 200 then
    helpers:unsuccessful_login_attempt(admin)
    return res
  end
  
  local _, err = helpers:successful_login_attempt(admin)

  if err then
    kong.log.err("failed login attempt:", err)
    return { code = 500, body = { message = "An unexpected error occurred" } }
  end
  
  return res
end


function _M.update_token(admin, params)
  local expired_ident = admin.rbac_user.user_token_ident

  if params and params.token then
    return { code = 400, body = { message = "Tokens cannot be set explicitly. Remove token parameter to receive an auto-generated token." }}
  end

  local token = utils.random_string()

  admin.rbac_user.user_token = token
  admin.rbac_user.user_token_ident = rbac.get_token_ident(token)

  if not admin.rbac_user.ws_id then
    local rbac_user, err = kong.db.rbac_users:select({id = admin.rbac_user.id}, {
      workspace = null, show_ws_id = true
    })

    if err then
      return nil, err
    end
    admin.rbac_user.ws_id = rbac_user.ws_id
  end
  local save_ws_id = admin.rbac_user.ws_id
  admin.rbac_user.ws_id = nil
  local check_result, err = kong.db.rbac_users.schema:validate(admin.rbac_user)
  if not check_result then
    local err_t = kong.db.errors:schema_violation(err)
    return nil, err_t
  end
  admin.rbac_user.ws_id = save_ws_id

  local _, err = kong.db.rbac_users:update(
    { id = admin.rbac_user.id },
    {
      user_token = admin.rbac_user.user_token,
      user_token_ident = admin.rbac_user.user_token_ident
    },
    { workspace = save_ws_id }
  )

  if err then
    return nil, err
  end

  if expired_ident then
    -- invalidate the cached token
    -- if there is a user token set
    local cache_key = "rbac_user_token_ident:" .. expired_ident
    if kong.cache then
      kong.cache:invalidate(cache_key)
    end
  end

  return { code = 200, body = { token = token, message = "Token reset successfully" }}
end

function _M.update_belong_workspace(admin, params)
  local workspace = workspaces.select_workspace_with_cache(params.workspaces)

  -- 1.update the admin's workspace
  local default_role = retrieve_default_role(admin.rbac_user)
  local _, err = kong.db.admins:update_workspaces(admin, default_role, workspace)
  if err then
    return nil, err
  end

  -- 2.invalidate the rbac_user related's cache
  local rbac_user_roles_cache_key = kong.db.rbac_user_roles:cache_key(admin.rbac_user.id)
  kong.cache:invalidate(rbac_user_roles_cache_key)

  -- If the administrator logs into Kong Manager first, the cache key 
  -- for caching consumers will be generated using the default workspace ID. 
  -- Therefore, it is necessary to clear the consumer's cache to ensure that the latest consumer data is loaded.
  local default_workspace = workspaces.select_workspace_with_cache("default")
  local consumer_cache_key = kong.db.consumers:cache_key(admin.consumer.id, nil, nil, nil, nil, default_workspace.id)
  kong.cache:invalidate(consumer_cache_key)

  -- clean the consumer's cache with the current workspace
  consumer_cache_key = kong.db.consumers:cache_key(admin.consumer.id, nil, nil, nil, nil, admin.consumer.ws_id)
  kong.cache:invalidate(consumer_cache_key)

  -- 3.recount the number of each entities.
  counters.initialize_counters(kong.db)

  return _M.find_by_username_or_id(admin.id, true, false)
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

  return { code = 204 }
end

function _M.find_by_username_or_id(username_or_id, raw, require_workspace_ctx)
  if require_workspace_ctx == nil then
    require_workspace_ctx = true
  end
  if not username_or_id then
    return nil
  end

  local admin, err

  if utils.is_valid_uuid(username_or_id) then
    admin, err = kong.db.admins:select({ id = username_or_id })
    if err then
      return nil, err
    end
  end

  if not admin then
    admin, err = kong.db.admins:select_by_username(username_or_id)
    if err then
      return nil, err
    end
  end
--
  if not admin then
    return nil
  end

  local rbac_user = kong.db.rbac_users:select(admin.rbac_user, { workspace = null, show_ws_id = true })

  local wss, _, err = rbac.find_all_ws_for_rbac_user(rbac_user, null, true)

  if err then
    return nil, err
  end

  admin.workspaces = wss
  admin.groups = rbac.get_user_groups(kong.db, rbac_user)
  admin.belong_workspace = workspaces.select_workspace_by_id_with_cache(rbac_user.ws_id)

  local c_ws_id = ngx.ctx.workspace

  if not c_ws_id then
    return raw and admin or transmogrify(admin)
  end

  local ws, err = workspaces.select_workspace_by_id_with_cache(c_ws_id)
  if not ws then
    return nil, err
  end

  local c_ws_name = ws and ws.name
  if not c_ws_name or not require_workspace_ctx then
    return raw and admin or transmogrify(admin)
  end

  -- see if this admin is in this workspace
  for _, ws in ipairs(wss) do
    if ws.name == c_ws_name or ws.name == '*' then
      return raw and admin or transmogrify(admin)
    end
  end
end


function _M.workspaces_for_admin(username_or_id)
  -- we need a full admin here, not a prettified one
  local admin, err = _M.find_by_username_or_id(username_or_id, true)
  if err then
    return nil, err
  end

  if not admin then
    return { code = 404, body = { message = "not found" } }
  end

  local rbac_user = kong.db.rbac_users:select(admin.rbac_user, { workspace = null, show_ws_id = true })
  local wss = rbac.find_all_ws_for_rbac_user(rbac_user, null, true)

  return {
    code = 200,
    body = setmetatable(wss, cjson.empty_array_mt),
  }
end


function _M.reset_password(plugin, collection, consumer, new_password, secret_id)
  log(DEBUG, _log_prefix, "searching ", plugin.name, "creds for consumer ", consumer.id)
  for row, err in collection:each_for_consumer({ id = consumer.id }, nil, { workspace = null, show_ws_id = true }) do
    if err then
      return nil, err
    end

    local _, err = collection:update(
      { id = row.id },
      {
        consumer = { id = consumer.id },
        [plugin.credential_key] = new_password,
      },
      { workspace = row.ws_id }
    )

    if err then
      return nil, err
    end

    -- invalidate auth credential cache
    -- could be removed after we migrates/creates consumer's ws_id to default ws id
    local cache_key = kong.db[plugin.dao]:cache_key(row.username, nil, nil, nil, nil, row.ws_id)
    kong.cache:invalidate(cache_key)
  end

  log(DEBUG, _log_prefix, "password was reset, updating secrets")
  local ok, err = secrets.consume_secret(secret_id)
  if not ok then
    return nil, err
  end

  return true
end

return _M
