local singletons = require "kong.singletons"
local enums = require "kong.enterprise_edition.dao.enums"
local secrets = require "kong.enterprise_edition.consumer_reset_secret_helpers"
local ee_utils = require "kong.enterprise_edition.utils"
local utils = require "kong.tools.utils"
local cjson = require "cjson"
local rbac = require "kong.rbac"
local auth_helpers = require "kong.enterprise_edition.auth_helpers"


local emails = singletons.admin_emails

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


function _M.find_all()
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
    v.workspaces = rbac.find_all_ws_for_rbac_user(rbac_user, null)

    for _, ws in ipairs(v.workspaces) do
      if ws.id == ngx.ctx.workspace or ws.name == '*' then
        ws_admins[#ws_admins + 1] = transmogrify(v)
        break
      end
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

    local expiry = singletons.configuration.admin_invitation_expiry
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

  local _, admin, err = _M.validate(safe_params, opts.db)

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
  local admin, err, err_t = singletons.db.admins:insert(params)

  -- error table is kong-generated schema violations
  if err_t then
    return {
      code = 400,
      body = err_t,
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
      log(ERR, _log_prefix, "error inviting user: ", admin.email)

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

  local db = opts.db or singletons.db

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
    -- update consumer
    local _, err = db.consumers:update(
    { id = admin_to_update.consumer.id },
    {
      username = params.username,
      custom_id = params.custom_id,
    }, { workspace = null })
    if err then
      return nil, err
    end

    -- if name changed, update basic-auth credential, if any
    if params.username ~= admin_to_update.username then
      local creds, err = db.basicauth_credentials:page_for_consumer(admin.consumer)
      if err then
        return nil, err
      end

      if creds[1] then
        local _, err = db.basicauth_credentials:update(
          { id = creds[1].id },
          { username = admin.username }, { workspace = null })
        if err then
          return nil, err
        end
      end
    end
  end

  -- keep rbac_user in sync
  if params.rbac_token_enabled ~= nil then
    local _, err = db.rbac_users:update(
      { id = admin_to_update.rbac_user.id },
      {
        enabled = params.rbac_token_enabled,
      }, {workspace = null})
    if err then
      return nil, err
    end
  end

  return { code = 200, body = transmogrify(admin) }
end


function _M.update_password(admin, params)
  local creds, bad_req_message, err = auth_helpers.verify_password(admin, params.old_password,
                                                      params.password)
  if err then
    return nil, err
  end

  if bad_req_message then
    return { code = 400, body = { message = bad_req_message }}
  end


  local _, err = kong.db.basicauth_credentials:update(
    { id = creds.id },
    {
      consumer = { id = admin.consumer.id },
      password = params.password,
    }, { workspace = null })

  if err then
    return nil, err
  end

  return { code = 200, body = { message = "Password reset successfully" }}
end


function _M.update_token(admin, params)
  local expired_ident = admin.rbac_user.user_token_ident

  if params.token then
    return { code = 400, body = { message = "Tokens cannot be set explicitly. Remove token parameter to receive an auto-generated token." }}
  end

  local token = utils.random_string()

  admin.rbac_user.user_token = token
  admin.rbac_user.user_token_ident = rbac.get_token_ident(token)

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
    { workspace = null }
  )

  if err then
    return nil, err
  end

  if expired_ident then
    -- invalidate the cached token
    -- if there is a user token set
    local cache_key = "rbac_user_token_ident:" .. expired_ident
    kong.cache:invalidate(cache_key)
  end

  return { code = 200, body = { token = token, message = "Token reset successfully" }}
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

  local wss, err = rbac.find_all_ws_for_rbac_user(rbac_user, null)

  admin.workspaces = wss

  if err then
    return nil, err
  end

  local c_ws_id = ngx.ctx.workspace

  if not c_ws_id then
    return raw and admin or transmogrify(admin)
  end

  local ws = kong.db.workspaces:select({ id = c_ws_id })
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
    return { code = 404, body = { message = "not found" }}
  end

  local rbac_user = kong.db.rbac_users:select(admin.rbac_user, { workspace = null, show_ws_id = true })
  local wss = rbac.find_all_ws_for_rbac_user(rbac_user, null)

  return {
    code = 200,
    body = setmetatable(wss, cjson.empty_array_mt),
  }
end


function _M.reset_password(plugin, collection, consumer, new_password, secret_id)
  log(DEBUG, _log_prefix, "searching ", plugin.name, "creds for consumer ", consumer.id)
  for row, err in collection:each_for_consumer({ id = consumer.id }, nil, { workspace = null }) do
    if err then
      return nil, err
    end

    local _, err = collection:update(
      { id = row.id },
      {
        consumer = { id = consumer.id },
        [plugin.credential_key] = new_password,
      },
      { workspace = null }
    )

    if err then
      return nil, err
    end
  end

  log(DEBUG, _log_prefix, "password was reset, updating secrets")
  local ok, err = secrets.consume_secret(secret_id)
  if not ok then
    return nil, err
  end

  return true
end

return _M
