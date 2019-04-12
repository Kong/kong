local endpoints   = require "kong.api.endpoints"
local singletons  = require "kong.singletons"
local enums       = require "kong.enterprise_edition.dao.enums"
local rbac        = require "kong.rbac"
local workspaces  = require "kong.workspaces"
local ee_utils    = require "kong.enterprise_edition.utils"
local ee_jwt      = require "kong.enterprise_edition.jwt"
local endpoints   = require "kong.api.endpoints"

local kong = kong
local log = ngx.log
local ERR = ngx.ERR
local DEBUG = ngx.DEBUG

local _M = {}


local _log_prefix = "[api_helpers] "


_M.apis = {
  ADMIN   = "admin",
  PORTAL  = "portal"
}

local auth_whitelisted_uris = {
  ["/admins/register"] = true,
  ["/admins/password_resets"] = true,
}


function _M.get_consumer_status(consumer)
  local status

  if consumer.type == enums.CONSUMERS.TYPE.DEVELOPER then
    local developer = singletons.db.developers:select_by_email(consumer.email)
    status = developer.status
  end

  return {
    status = status,
    label  = enums.CONSUMERS.STATUS_LABELS[status],
  }
end


function _M.retrieve_consumer(consumer_id)
  local consumer, err = kong.db.consumers:select({
    id = consumer_id
  })
  if err then
    log(ERR, "error in retrieving consumer:" .. consumer_id, err)
    return nil, err
  end


  return consumer or nil
end


--- Authenticate the incoming request checking for rbac users and admin
--  consumer credentials
--
function _M.authenticate(self, rbac_enabled, gui_auth)
  local ctx = ngx.ctx
  local invoke_plugin = singletons.invoke_plugin

  -- no authentication required? nothing to do here.
  if not gui_auth and not rbac_enabled then
    return
  end

  -- lookup to see if we white listed this route from auth checks
  if auth_whitelisted_uris[ngx.var.uri] then
    return
  end

  -- only RBAC is on? let the rbac module handle it
  if rbac_enabled and not gui_auth then
    return
  end

  -- execute rbac and auth check without a workspace specified
  local old_ws = ctx.workspaces
  ctx.workspaces = {}

  -- Once we get here we know rbac_token and gui_auth are both enabled
  -- and we need to run authentication checks
  local user_header = singletons.configuration.admin_gui_auth_header
  local user_name = ngx.req.get_headers()[user_header]
  if not user_name then
    return kong.response.exit(401, {
      message = "Invalid RBAC credentials. Token or User credentials required"
    })
  end

  local admin, err = kong.db.admins:select_by_username(user_name)

  if not admin then
    log(DEBUG, _log_prefix, "Admin not found with user_name=" .. user_name)
    return kong.response.exit(401, { message = "Unauthorized" })
  end

  if err then
    log(ERR, _log_prefix, err)
    return endpoints.handle_error(err)
  end

  local consumer_id = admin.consumer.id
  local rbac_user_id = admin.rbac_user.id
  local rbac_user, err = rbac.get_user(rbac_user_id)

  if err then
    log(ERR, _log_prefix, err)
    return endpoints.handle_error(err)
  end

  if not rbac_user then
    log(DEBUG, _log_prefix, "no rbac_user found for name: ", user_name)
    return kong.response.exit(401, { message = "Unauthorized" })
  end

  -- sets self.workspace_entities, ngx.ctx.workspaces, and self.consumer
  _M.attach_consumer_and_workspaces(self, consumer_id)

  -- apply auth plugin
  local auth_conf = singletons.configuration.admin_gui_auth_conf
  local session_conf = singletons.configuration.admin_gui_session_conf

  -- run the session plugin access to see if we have a current session
  -- with a valid authenticated consumer.
  local ok, err = invoke_plugin({
    name = "session",
    config = session_conf,
    phases = { "access" },
    api_type = _M.apis.ADMIN,
    db = kong.db,
  })

  if not ok then
    log(ERR, _log_prefix, err)
    return endpoints.handle_error(err)
  end

  -- if we don't have a valid session, run the gui authentication plugin
  if not ngx.ctx.authenticated_consumer then
    local ok, err = invoke_plugin({
      name = gui_auth,
      config = auth_conf,
      phases = { "access" },
      api_type = _M.apis.ADMIN,
      db = kong.db,
    })

    if not ok then
      log(ERR, _log_prefix, err)
      return endpoints.handle_error(err)
    end
  end

  if not ok then
    return endpoints.handle_error(err)
  end

  -- Plugin ran but consumer was not created on context
  if not ctx.authenticated_consumer then
    log(ERR, _log_prefix, "no consumer mapped from plugin", gui_auth)
    return kong.response.exit(401, { message = "Unauthorized" })
  end

  if self.consumer and ctx.authenticated_consumer.id ~= self.consumer.id then
    log(ERR, _log_prefix, "authenticated consumer is not an admin")
    return kong.response.exit(401, { message = "Unauthorized" })
  end

  local ok, err = invoke_plugin({
    name = "session",
    config = session_conf,
    phases = { "header_filter" },
    api_type = _M.apis.ADMIN,
    db = kong.db,
  })

  if not ok then
    log(ERR, _log_prefix, err)
    return endpoints.handle_error(err)
  end

  self.consumer = ctx.authenticated_consumer

  if self.consumer.type ~= enums.CONSUMERS.TYPE.ADMIN then
    log(ERR, _log_prefix, "consumer ", self.consumer.id, " is not an admin")
    return kong.response.exit(401, { message = "Unauthorized" })
  end

  -- consumer transitions from INVITED to APPROVED on first successful login
  if admin.status == enums.CONSUMERS.STATUS.INVITED then
    local _, err = kong.db.admins:update({ id = admin.id },
                                   { status = enums.CONSUMERS.STATUS.APPROVED })

    if err then
      log(ERR, _log_prefix, "failed to approve admin: ", admin.id, ": ", err)
      return endpoints.handle_error(err)
    end

    admin.status = enums.CONSUMERS.STATUS.APPROVED
  end

  if admin.status ~= enums.CONSUMERS.STATUS.APPROVED then
    return kong.response.exit(401, _M.get_consumer_status(admin))
  end

  self.rbac_user = rbac_user
  self.admin = admin
  -- set back workspace context from request
  ctx.workspaces = old_ws
end


function _M.attach_consumer_and_workspaces(self, consumer_id)
  local workspace = _M.attach_workspaces(self, consumer_id)

  ngx.ctx.workspaces = { workspace }

  _M.attach_consumer(self, consumer_id)
end


function _M.attach_consumer(self, consumer_id)
  local cache_key = kong.db.consumers:cache_key(consumer_id)
  local consumer, err = kong.cache:get(cache_key, nil, _M.retrieve_consumer,
                                       consumer_id)

  if err or not consumer then
    log(ERR, _log_prefix, "failed to get consumer:", consumer_id, ": ", err)
    return endpoints.handle_error()
  end

  self.consumer = consumer
end


function _M.attach_workspaces(self, consumer_id)
  local workspace_entities, err = kong.db.workspace_entities:select_all({
    entity_id = consumer_id,
    unique_field_name = "id",
    entity_type = "consumers",
  })

  self.workspace_entities = workspace_entities

  if err then
    log(ERR, _log_prefix, "Error fetching workspaces for consumer: ",
        consumer_id, ": ", err)
    return endpoints.handle_error()
  end

  if not next(workspace_entities) then
    log(ERR, "no workspace found for consumer:" .. consumer_id)
    return endpoints.handle_error()
  end

  return {
    id = self.workspace_entities[1].workspace_id,
    name = self.workspace_entities[1].workspace_name,
  }
end


-- given an entity uuid, look up its entity collection name;
-- it is only called if the user does not pass in an entity_type
function _M.resolve_entity_type(new_dao, old_dao, entity_id)

  -- the workspaces module has a function that does a similar search in
  -- a constant number of db calls, but is restricted to workspaceable
  -- entities. try that first; if it isn't able to resolve the entity
  -- type, continue our linear search
  local typ, entity, _ = workspaces.resolve_entity_type(entity_id)
  if typ and entity then
    return typ, entity, nil
  end

  -- search in all of old dao
  for name, dao in pairs(old_dao.daos) do
    local pk_name = dao.schema.primary_key[1]
    -- XXX old-dao: if branch is going away with old dao
    if dao.schema.fields[pk_name].type == "id" then
      local rows, err = dao:find_all({
        [pk_name] = entity_id,
      })
      if err then
        return nil, nil, err
      end
      if rows[1] then
        return name, rows[1], nil
      end
    end
  end

  -- search in all of new dao
  for name, dao in pairs(new_dao.daos) do
    local pk_name = dao.schema.primary_key[1]
    if dao.schema.fields[pk_name].uuid then
      local row = dao:select({
        [pk_name] = entity_id,
      })
      if row then
        return name, row, nil
      end
    end
  end

  return false, nil, "entity " .. entity_id .. " does not belong to any relation"
end


function _M.validate_jwt(self, db, helpers, token_optional)
  local reset_secrets = db.consumer_reset_secrets

  -- Verify params
  if token_optional then
    return
  end

  if not self.params.token or self.params.token == "" then
    return kong.response.exit(400, { message = "token is required" })
  end

  -- Parse and ensure that jwt contains the correct claims/headers.
  -- Signature NOT verified yet
  local jwt, err = ee_utils.validate_reset_jwt(self.params.token)
  if err then
    return kong.response.exit(401, { message = "Unauthorized" })
  end

  -- Look up the secret by consumer id
  local reset_secret
  for secret, err in reset_secrets:each_for_consumer({ id = jwt.claims.id }) do
    if err then
      log(ERR, _log_prefix, err)
      return kong.response.exit(401, { message = "Unauthorized" })
    end

    if not reset_secret and secret.status == enums.TOKENS.STATUS.PENDING then
      reset_secret = secret
    end
  end

  if not reset_secret then
    return kong.response.exit(401, { message = "Unauthorized"})
  end

  -- Generate a new signature and compare it to passed token
  local ok, _ = ee_jwt.verify_signature(jwt, reset_secret.secret)
  if not ok then
    log(ERR, _log_prefix, "JWT signature is invalid")
    return kong.response.exit(401, { message = "Unauthorized" })
  end

  self.reset_secret_id = reset_secret.id
  self.consumer_id = jwt.claims.id
end


function _M.validate_email(self, dao_factory, helpers)
  local ok, err = ee_utils.validate_email(self.params.email)
  if not ok then
    return kong.response.exit(400, { message = "Invalid email: " .. err })
  end
end


function _M.routes_consumers_before(self, params, is_collection)
  if params.type then
    return kong.response.exit(400, { message = "Invalid parameter: 'type'" })
  end

  if is_collection then
    return true
  end

  -- PUT creates if consumer doesn't exist, so exit early
  if kong.request.get_method() == "PUT" then
    return
  end

  local consumer, _, err_t = endpoints.select_entity(self, kong.db,
                                                     kong.db.consumers.schema)
  if err_t then
    return endpoints.handle_error(err_t)
  end

  if not consumer then
    return kong.response.exit(404, { message = "Not found" })
  end

  if consumer.type ~= enums.CONSUMERS.TYPE.PROXY then
    return kong.response.exit(404, { message = "Not Found" })
  end

  return consumer
end


return _M
