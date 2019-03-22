local crud       = require "kong.api.crud_helpers"
local enums      = require "kong.enterprise_edition.dao.enums"
local utils      = require "kong.tools.utils"
local rbac       = require "kong.rbac"
local workspaces = require "kong.workspaces"
local singletons = require "kong.singletons"
local admins     = require "kong.enterprise_edition.admins_helpers"
local ee_api     = require "kong.enterprise_edition.api_helpers"
local tablex     = require "pl.tablex"
local secrets = require "kong.enterprise_edition.consumer_reset_secret_helpers"
local new_tab = require "table.new"
local cjson = require "cjson"


local emails = singletons.admin_emails

local log = ngx.log
local ERR = ngx.ERR
local DEBUG = ngx.DEBUG

local _log_prefix = "[admins] "

local entity_relationships = rbac.entity_relationships


--- Allowed auth plugins
-- Table containing allowed auth plugins that the developer portal api
-- can create credentials for.
--
--["<route>"]:     {  name = "<name>",    dao = "<dao_collection>" }
local auth_plugins = {
  ["basic-auth"] = {
    name = "basic-auth",
    dao = "basicauth_credentials",
    credential_key = "password"
  },
  ["key-auth"] =   {
    name = "key-auth",
    dao = "keyauth_credentials",
    credential_key = "key"
  },
  ["ldap-auth-advanced"] = { name = "ldap-auth-advanced" },
}


local function objects_from_names(dao_factory, given_names, object_name)
  local names = utils.split(given_names, ",")
  local objs = new_tab(#names, 0)
  local object_dao = string.format("rbac_%ss", object_name)

  for i = 1, #names do
    local object, err = dao_factory[object_dao]:find_all({
      name = names[i],
    })
    if err then
      return nil, err
    end

    if not object[1] then
      return nil, string.format("%s not found with name '%s'", object_name, names[i])
    end

    -- track the whole object so we have the id for the mapping later
    objs[i] = object[1]
  end

  return objs
end


local function validate_auth_plugin(self, dao_factory, helpers, plugin_name)
  local gui_auth = singletons.configuration.admin_gui_auth
  plugin_name = plugin_name or gui_auth
  self.plugin = auth_plugins[plugin_name]
  if not self.plugin and gui_auth then
    return helpers.responses.send_HTTP_NOT_FOUND()
  end

  if self.plugin and self.plugin.dao then
    self.collection = dao_factory[self.plugin.dao]
  else
    self.token_optional = true
  end
end


local function set_rbac_user(self, dao_factory, helpers)
  -- Lookup the rbac_user<->consumer map
  local maps, err = dao_factory.consumers_rbac_users_map:find_all({
    consumer_id = self.consumer.id
  })

  if err then
    helpers.yield_error(err)
  end

  local map = maps[1]

  if not map then
    log(ERR, _log_prefix, "No rbac mapping found for consumer ", self.consumer.id)
    helpers.responses.send_HTTP_INTERNAL_SERVER_ERROR()
  end

  -- Find the rbac_user associated with the consumer
  local users, err = dao_factory.rbac_users:find_all({
    id = map.user_id
  })

  if err then
    helpers.yield_error(err)
  end

  -- Set the rbac_user on the consumer entity
  local rbac_user = users[1]

  if not rbac_user then
    log(ERR, _log_prefix, "No RBAC user found for consumer ", map.consumer_id,
        " and rbac user ", map.user_id)
    helpers.responses.send_HTTP_INTERNAL_SERVER_ERROR()
  end

  rbac_user.user_token = nil
  self.consumer.rbac_user = rbac_user
  self.rbac_user = rbac_user
end


return {
  ["/admins"] = {
    before = function(self, db, helpers, parent)
       validate_auth_plugin(self, db, helpers)
    end,

    GET = function(self, db, helpers, parent)
      local res, err = admins.find_all()

      if err then
        return helpers.responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
      end

      return helpers.responses.send(res.code, res.body)
    end,

    POST = function(self, db, helpers, parent)
      local res, err = admins.create(self.params, {
        token_optional = self.token_optional,
        workspace = ngx.ctx.workspaces[1],
        db = db,
      })

      if err then
        return helpers.responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
      end

      return helpers.responses.send(res.code, res.body)
    end,
  },

  ["/admins/:admins"] = {
    before = function(self, db, helpers, parent)
      local err

      self.admin, err = admins.find_by_username_or_id(ngx.unescape_uri(self.params.admins))
      if err then
        return helpers.responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
      end

      if not self.admin then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end
    end,

    GET = function(self, db, helpers, parent)
      local opts = { generate_register_url = self.params.generate_register_url }

      local res, err = admins.generate_token(self.admin, opts)
      if err then
        return helpers.yield_error(err)
      end

      return helpers.responses.send(res.code, res.body)
    end,

    PATCH = function(self, db, helpers, parent)
      local res, err = admins.update(self.params, self.admin, { db = db })
      if err then
        return helpers.yield_error(err)
      end

      return helpers.responses.send(res.code, res.body)
    end,

    DELETE = function(self, db, helpers, parent)
      local res, err = admins.delete(self.admin, { db = db })
      if err then
        return helpers.yield_error(err)
      end

      return helpers.responses.send(res.code, res.body)
    end
  },

  ["/admins/:username_or_id/roles"] = {
    before = function(self, dao_factory, helpers)
      self.params.username_or_id = ngx.unescape_uri(self.params.username_or_id)
      crud.find_consumer_by_username_or_id(self, dao_factory, helpers)

      if self.consumer.type ~= enums.CONSUMERS.TYPE.ADMIN then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      set_rbac_user(self, dao_factory, helpers)
    end,

    GET = function(self, dao_factory, helpers)
      local roles, err = entity_relationships(dao_factory, self.rbac_user,
        "user", "role")

      if err then
        return helpers.yield_error(err)
      end

      -- filter out default roles
      roles = tablex.filter(roles, function(role) return not role.is_default end)

      setmetatable(roles, cjson.empty_array_mt)

      return helpers.responses.send_HTTP_OK({
        roles = roles,
      })
    end,

    POST = function(self, dao_factory, helpers)
      -- we have the user, now verify our roles
      if not self.params.roles then
        return helpers.responses.send_HTTP_BAD_REQUEST("must provide >= 1 role")
      end

      local roles, err = objects_from_names(dao_factory, self.params.roles,
        "role")
      if err then
        if err:find("not found with name", nil, true) then
          return helpers.responses.send_HTTP_BAD_REQUEST(err)

        else
          return helpers.yield_error(err)
        end
      end

      -- we've now validated that all our roles exist, and this user exists,
      -- so time to create the assignment
      for i = 1, #roles do
        local _, err = dao_factory.rbac_user_roles:insert({
          user_id = self.rbac_user.id,
          role_id = roles[i].id
        })
        if err then
          return helpers.yield_error(err)
        end
      end

      -- invalidate rbac user so we don't fetch the old roles
      local cache_key = dao_factory["rbac_user_roles"]:cache_key(self.rbac_user.id)
      singletons.cache:invalidate(cache_key)

      -- re-fetch the users roles so we show all the role objects, not just our
      -- newly assigned mappings
      roles, err = entity_relationships(dao_factory, self.rbac_user,
        "user", "role")
      if err then
        return helpers.yield_error(err)
      end

      -- filter out default roles
      roles = tablex.filter(roles, function(role) return not role.is_default end)

      -- show the user and all of the roles they are in
      return helpers.responses.send_HTTP_CREATED({
        roles = roles,
      })
    end,

    DELETE = function(self, dao_factory, helpers)
      -- we have the user, now verify our roles
      if not self.params.roles then
        return helpers.responses.send_HTTP_BAD_REQUEST("must provide >= 1 role")
      end

      local roles, err = objects_from_names(dao_factory, self.params.roles,
        "role")
      if err then
        if err:find("not found with name", nil, true) then
          return helpers.responses.send_HTTP_BAD_REQUEST(err)

        else
          return helpers.yield_error(err)
        end
      end

      for i = 1, #roles do
        dao_factory.rbac_user_roles:delete({
          user_id = self.rbac_user.id,
          role_id = roles[i].id,
        })
      end

      local cache_key = dao_factory["rbac_users"]:cache_key(self.rbac_user.id)
      singletons.cache:invalidate(cache_key)

      return helpers.responses.send_HTTP_NO_CONTENT()
    end,
  },

  ["/admins/password_resets"] = {
    before = function(self, dao_factory, helpers)
      validate_auth_plugin(self, dao_factory, helpers)

      -- if we don't store your creds, you don't belong here
      if self.token_optional then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      if not self.params.email or self.params.email == "" then
        return helpers.responses.send_HTTP_BAD_REQUEST("email is required")
      end

      -- if you've forgotten your password, this is all we know about you
      self.consumer = admins.find_by_email(self.params.email)
      if not self.consumer then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      -- when you reset your password, you come in with an email and a JWT
      -- if it's there, make sure it's good
      if self.params.token then
        ee_api.validate_jwt(self, dao_factory, helpers)

        -- make sure the email in the query params matches the one in the token
        if self.consumer_id ~= self.consumer.id then
          return helpers.responses.send_HTTP_NOT_FOUND()
        end
      end
    end,

    -- create a password reset request and send mail
    POST = function(self, dao_factory, helpers)
      local expiry = singletons.configuration.admin_invitation_expiry

      local jwt, err = secrets.create(self.consumer, ngx.var.remote_addr, expiry)

      if err then
        log(ERR, _log_prefix, "failed to generate password reset token: ", err)
        return helpers.responses.send_HTTP_INTERNAL_SERVER_ERROR()
      end

      -- send mail
      local _, err = emails:reset_password(self.consumer.email, jwt)
      if err then
        log(ERR, _log_prefix, "failed to send reset_password email for: ",
          self.consumer.email)

        return helpers.responses.send_HTTP_INTERNAL_SERVER_ERROR()
      end

      return helpers.responses.send_HTTP_CREATED()
    end,

    -- reset password and consume token
    PATCH = function(self, dao_factory, helpers)
      local new_password = self.params.password
      if not new_password or new_password == "" then
        return helpers.responses.send_HTTP_BAD_REQUEST("password is required")
      end

      local found, err = admins.reset_password(self.plugin,
                                               self.collection,
                                               self.consumer,
                                               new_password,
                                               self.reset_secret_id)

      if err then
        return helpers.yield_error(err)
      end

      if not found then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      local _, err = emails:reset_password_success(self.consumer.email)
      if err then
        return helpers.yield_error(err)
      end

      return helpers.responses.send_HTTP_OK()
    end
  },

  ["/admins/:consumer_id/workspaces"] = {
    before = function(self, dao_factory, helpers)
      self.params.consumer_id = ngx.unescape_uri(self.params.consumer_id)
      crud.find_consumer_rbac_user_map(self, dao_factory, helpers)
    end,

    GET = function(self, dao_factory, helpers)
      local old_ws = ngx.ctx.workspaces
      ngx.ctx.workspaces = {}

      local rows, err = workspaces.find_workspaces_by_entity({
        entity_id = self.consumer_rbac_user_map.user_id,
        unique_field_name = "id",
      })

      if err then
        log(ERR, _log_prefix, "error fetching workspace for rbac user: ",
           self.consumer_rbac_user_map.user_id, ": ", err)
      end

      local wrkspaces = {}
      for i, workspace in ipairs(rows) do
        local ws, err = dao_factory.workspaces:find({
          id = workspace.workspace_id
        })
        if err then
          log(ERR, _log_prefix, "error fetching workspace: ", err)
          return helpers.responses.send_HTTP_INTERNAL_SERVER_ERROR()
        end

        if ws then
          -- only fetch the consumer from the first workspace
          -- to avoid extraneous lookups
          if i == 1 then
            ngx.ctx.workspaces = { ws }
            local consumer, err = dao_factory.consumers:find({
              id = self.params.consumer_id
            })
            ngx.ctx.workspaces = {}

            if err then
              log(ERR, _log_prefix, "error fetching consumer in workspace: ",
                  ws.workspace_name, ": ", err)
            end

            if not consumer then
              log(DEBUG, _log_prefix, "no consumer found in workspace: ",
                  ws.workspace_name)
              helpers.responses.send_HTTP_NOT_FOUND()
            end

            if consumer.type ~= enums.CONSUMERS.TYPE.ADMIN then
              log(DEBUG, _log_prefix, "consumer is not of type admin")
              helpers.responses.send_HTTP_NOT_FOUND()
            end
          end

          wrkspaces[i] = ws
        end
      end

      ngx.ctx.workspaces = old_ws
      helpers.responses.send_HTTP_OK(wrkspaces)
    end
  },

  ["/admins/register"] = {
    before = function(self, dao_factory, helpers)
      validate_auth_plugin(self, dao_factory, helpers)
      if self.token_optional then
        return helpers.responses.send_HTTP_BAD_REQUEST("cannot register " ..
                                                       "with admin_gui_auth = "
                                                       .. self.plugin.name)
      end
      ee_api.validate_email(self, dao_factory, helpers)
      ee_api.validate_jwt(self, dao_factory, helpers)
    end,

    POST = function(self, dao_factory, helpers)
      if not self.consumer_id then
        log(ERR, _log_prefix, "consumer not found for registration")
        return helpers.responses.send_HTTP_UNAUTHORIZED()
      end

      local rows, err = workspaces.run_with_ws_scope({},
                                    dao_factory.consumers.find_all,
                                    dao_factory.consumers,
                                    {
                                      id = self.consumer_id,
                                    })
      if err then
        helpers.yield_error(err)
      end

      if not next(rows) then
        return helpers.responses.send_HTTP_UNAUTHORIZED()
      end

      local consumer = rows[1]
      local credential_data

      if consumer.email ~= self.params.email then
        return helpers.responses.send_HTTP_UNAUTHORIZED()
      end

      -- create credential object based on admin_gui_auth
      if self.plugin.name == "basic-auth" then
        credential_data = {
          consumer_id = consumer.id,
          username = consumer.username,
          password = self.params.password,
        }
      end

      if self.plugin.name == "key-auth" then
        credential_data = {
          consumer_id = consumer.id,
          key = self.params.password,
        }
      end

      if credential_data == nil then
        return helpers.responses.send_HTTP_BAD_REQUEST(
          "Cannot create credential with admin_gui_auth = " ..
          self.plugin.name)
      end

      -- Find the workspace the consumer is in
      local refs, err = dao_factory.workspace_entities:find_all{
        entity_type = "consumers",
        entity_id = consumer.id,
        unique_field_name = "id",
      }

      if err then
        helpers.yield_error(err)
      end

      -- Set the current workspace so the credential is created there
      local workspace = {
        id = refs[1].workspace_id,
        name = refs[1].workspace_name,
      }
      ngx.ctx.workspaces = { workspace }

      crud.post(credential_data, self.collection, function(credential)
        crud.portal_crud.insert_credential(self.plugin.name,
                                           enums.CONSUMERS.TYPE.ADMIN
                                          )(credential)
        local res = {
          consumer = consumer,
          credential = credential,
        }

        if consumer.status == enums.CONSUMERS.STATUS.INVITED then
          dao_factory.consumers:update({status = enums.CONSUMERS.STATUS.APPROVED},
                                      {id = consumer.id})
        end

        -- Mark the token secret as consumed
        local _, err = singletons.dao.consumer_reset_secrets:update({
          status = enums.TOKENS.STATUS.CONSUMED,
          updated_at = ngx.now() * 1000,
        }, {
          id = self.reset_secret_id,
        })

        if err then
          helpers.yield_error(err)
        end

        return res
      end)
    end,
  },
}
