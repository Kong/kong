local constants   = require "kong.constants"
local singletons  = require "kong.singletons"
local api_helpers = require "lapis.application"
local enums       = require "kong.enterprise_edition.dao.enums"
local responses   = require "kong.tools.responses"
local rbac        = require "kong.rbac"
local utils       = require "kong.tools.utils"
local workspaces  = require "kong.workspaces"
local ee_utils    = require "kong.enterprise_edition.utils"
local ee_jwt      = require "kong.enterprise_edition.jwt"

local log = ngx.log
local ERR = ngx.ERR

local _M = {}


local _log_prefix = "[api_helpers] "


_M.apis = {
  ADMIN   = "admin",
  PORTAL  = "portal"
}


_M.services = {
  [_M.apis.PORTAL] = {
    id = "00000000-0000-0000-0000-000000000000",
    plugins = {},
  },
  [_M.apis.ADMIN]  = {
    id = "00000000-0000-0000-0000-000000000001",
    plugins = {},
  },
}

-- cache of admin plugin configurations
local admin_plugin_models = {}


local auth_whitelisted_uris = {
  ["/admins/register"] = true,
  ["/admins/password_resets"] = true,
}

function _M.get_consumer_id_from_headers()
  return ngx.req.get_headers()[constants.HEADERS.CONSUMER_ID]
end


function _M.get_consumer_status(consumer)
  local status = consumer.status

  return {
    status = status,
    label  = enums.CONSUMERS.STATUS_LABELS[status],
  }
end


function _M.prepare_plugin(type, dao, name, config)
  local plugin, err = _M.find_plugin(type, name)
  if err then
    return api_helpers.yield_error(err)
  end

  local fields = {
    name = plugin.name,
    service_id = _M.services[type].id,
    config = config
  }

  local model

  if type == _M.apis.ADMIN then
    model = admin_plugin_models[plugin.name]
  end

  if not model then
    -- convert plugin configuration over to model to obtain defaults
    model = dao.plugins.model_mt(fields)

    -- only cache valid models
    local ok, err = model:validate({dao = dao.plugins})
    if not ok then
      -- this config is invalid -- throw errors until the user fixes it
      return api_helpers.yield_error(err)
    end

    if type == _M.apis.ADMIN then
      admin_plugin_models[plugin.name] = model
    end
  end

  return {
    handler = plugin.handler,
    config = model.config,
  }
end


function _M.apply_plugin(plugin, phase)
  local err = coroutine.wrap(plugin.handler[phase])(plugin.handler, plugin.config)
  if err then
    return api_helpers.yield_error(err)
  end
end


function _M.find_plugin(type, name)
  if _M.services[type].plugins[name] then
    return _M.services[type].plugins[name]
  end

  for _, plugin in ipairs(singletons.loaded_plugins) do
    if plugin.name == name then
      _M.services[type].plugins[name] = plugin
      return plugin
    end
  end

  return nil, "plugin not found"
end


function _M.retrieve_consumer(consumer_id)
  local consumers, err = singletons.dao.consumers:find_all({
    id = consumer_id
  })
  if err then
    ngx.log(ngx.ERR, "error in retrieving consumer:" .. consumer_id, err)
    return nil, err
  end

  if not next(consumers) then
    return nil
  end

  return consumers[1]
end


--- Authenticate the incoming request checking for rbac users and admin
--  consumer credentials
--
function _M.authenticate(self, dao_factory, rbac_enabled, gui_auth)
  local ctx = ngx.ctx

  -- no authentication required? nothing to do here.
  if not gui_auth and not rbac_enabled then
    return
  end

  -- only RBAC is on? let the rbac module handle it
  if rbac_enabled and not gui_auth then
    return
  end

  -- execute rbac and auth check without a workspace specified
  if rbac_enabled then

    local old_ws = ctx.workspaces
    ctx.workspaces = {}

    local rbac_token = rbac.get_rbac_token()

    if not rbac_token and not gui_auth then
      return responses.send_HTTP_UNAUTHORIZED("Invalid RBAC credentials")
    end

    -- if you have the rbac token you can bypass plugin run loop but if
    -- gui_auth is enabled with no rbac_token, do plugin run loop
    if not rbac_token and gui_auth then
      local auth_whitelisted = auth_whitelisted_uris[ngx.var.request_uri]
      if auth_whitelisted then
        ctx.workspaces = old_ws
        return
      end

      local user_name = ngx.req.get_headers()['Kong-Admin-User']

      if not user_name then
        return responses.send_HTTP_UNAUTHORIZED("Invalid RBAC credentials. " ..
                                         "Token or User credentials required")
      end

      -- in 0.33, the rbac_user created with an admin consumer "foo" was named
      -- "user-foo". Support both naming conventions.
      local rbac_user, err
      for _, nm in ipairs({ user_name, "user-" .. user_name }) do
        rbac_user, err = rbac.get_user(nm, "name")
        if err then
          ngx.log(ngx.ERR, _log_prefix, err)
          return responses.send_HTTP_INTERNAL_SERVER_ERROR()
        end

        if rbac_user then
          break
        end
      end

      if not rbac_user then
        ngx.log(ngx.DEBUG, _log_prefix, "no rbac_user found for name: ", user_name)
        return responses.send_HTTP_UNAUTHORIZED()
      end

      rbac_token = rbac_user.user_token

      local consumer_user, err = rbac.get_consumer_user_map(rbac_user.id)

      if err then
        ngx.log(ngx.ERR, _log_prefix, err)
        return responses.send_HTTP_INTERNAL_SERVER_ERROR()
      end

      if not consumer_user then
        ngx.log(ngx.DEBUG, _log_prefix, "no consumer mapping for rbac_user: ",
                rbac_user.name)
        return responses.send_HTTP_UNAUTHORIZED()
      end

      local consumer_id = consumer_user.consumer_id

      local refs, err = dao_factory.workspace_entities:find_all{
        entity_id = consumer_id,
        unique_field_name = "id",
      }

      if err then
        ngx.log(ngx.ERR, _log_prefix, "Error fetching workspaces for consumer: ",
                consumer_id, ": ", err)
        return responses.send_HTTP_INTERNAL_SERVER_ERROR()
      end

      if not next(refs) then
        ngx.log(ngx.DEBUG, "no workspace found for consumer:" .. consumer_id)
        return responses.send_HTTP_INTERNAL_SERVER_ERROR()
      end

      local cache_key = dao_factory.consumers:cache_key(consumer_id)
      local consumer, err = singletons.cache:get(cache_key, nil,
                                                 _M.retrieve_consumer,
                                                 consumer_id)

      if err then
        ngx.log(ngx.ERR, _log_prefix, "error getting consumer: ", consumer_id)
        return responses.send_HTTP_INTERNAL_SERVER_ERROR()
      end

      if not consumer then
        ngx.log(ngx.DEBUG, _log_prefix, "consumer not found: ", consumer_id)
        return responses.send_HTTP_INTERNAL_SERVER_ERROR()
      end

      local workspace = {
        id = refs[1].workspace_id,
        name = refs[1].workspace_name,
      }

      self.consumer = consumer

      ctx.workspaces = { workspace }

      -- apply auth plugin
      local auth_conf = utils.deep_copy(singletons.configuration.admin_gui_auth_conf
                                        or {})
      local prepared_plugin = _M.prepare_plugin(_M.apis.ADMIN,
                                                    dao_factory,
                                                    gui_auth, auth_conf)
      _M.apply_plugin(prepared_plugin, "access")

      -- Plugin ran but consumer was not created on context
      if not ctx.authenticated_consumer then
        ngx.log(ngx.ERR, _log_prefix, "no consumer mapped from plugin", gui_auth)

        return responses.send_HTTP_UNAUTHORIZED()
      end

      if self.consumer and ctx.authenticated_consumer.id ~= consumer_id then
        ngx.log(ngx.ERR, _log_prefix, "no rbac user mapped with these credentials")

        return responses.send_HTTP_UNAUTHORIZED()
      end

      self.consumer = ctx.authenticated_consumer

      if self.consumer.type ~= enums.CONSUMERS.TYPE.ADMIN then
        ngx.log(ngx.ERR, _log_prefix, "consumer ", self.consumer.id, " is not an admin")
        return responses.send_HTTP_UNAUTHORIZED()
      end

      -- consumer transitions from INVITED to APPROVED on first successful login
      if self.consumer.status == enums.CONSUMERS.STATUS.INVITED then
        self.consumer, err = dao_factory.consumers:update(
                             { status = enums.CONSUMERS.STATUS.APPROVED },
                             { id = self.consumer.id})

        if err then
          ngx.log(ngx.ERR, _log_prefix, "failed to approve consumer: ",
                  self.consumer.id, ". err: ", err)

          return responses.send_HTTP_INTERNAL_SERVER_ERROR()
        end

        ctx.authenticated_consumer = self.consumer
      end

      if self.consumer.status ~= enums.CONSUMERS.STATUS.APPROVED then
        return responses.send_HTTP_UNAUTHORIZED(_M.get_consumer_status(consumer))
      end
    end

    ngx.req.set_header(singletons.configuration.rbac_auth_header, rbac_token)

    -- set back workspace context from request
    ctx.workspaces = old_ws
  end
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
      local row, err = dao:select({
        [pk_name] = entity_id,
      })
      if err then
        return nil, nil, err
      end
      if row then
        return name, row, nil
      end
    end
  end

  return false, nil, "entity " .. entity_id .. " does not belong to any relation"
end


function _M.validate_jwt(self, dao_factory, helpers, token_optional)
  -- Verify params
  if token_optional then
    return
  end

  if not self.params.token or self.params.token == "" then
    return helpers.responses.send_HTTP_BAD_REQUEST("token is required")
  end

  -- Parse and ensure that jwt contains the correct claims/headers.
  -- Signature NOT verified yet
  local jwt, err = ee_utils.validate_reset_jwt(self.params.token)
  if err then
    return helpers.responses.send_HTTP_UNAUTHORIZED(err)
  end

  -- Look up the secret by consumer id and pending status
  local rows, err = singletons.dao.consumer_reset_secrets:find_all({
    consumer_id = jwt.claims.id,
    status = enums.TOKENS.STATUS.PENDING,
  })

  if err then
    return helpers.responses.send_HTTP_UNAUTHORIZED(err)
  end

  if not rows or next(rows) == nil then
    return helpers.responses.send_HTTP_UNAUTHORIZED()
  end

  local reset_secret = rows[1]

  -- Generate a new signature and compare it to passed token
  local ok, _ = ee_jwt.verify_signature(jwt, reset_secret.secret)
  if not ok then
    log(ERR, _log_prefix, "JWT signature is invalid")
    return helpers.responses.send_HTTP_UNAUTHORIZED()
  end

  self.params.email_or_id = jwt.claims.id
  self.reset_secret_id = reset_secret.id
  self.consumer_id = jwt.claims.id
end


function _M.validate_email(self, dao_factory, helpers)
  local ok, err = ee_utils.validate_email(self.params.email)
  if not ok then
    return helpers.responses.send_HTTP_BAD_REQUEST("Invalid email: " .. err)
  end
end


return _M
