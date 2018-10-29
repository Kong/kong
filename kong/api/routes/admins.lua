local crud       = require "kong.api.crud_helpers"
local enums      = require "kong.enterprise_edition.dao.enums"
local utils      = require "kong.tools.utils"
local ee_crud    = require "kong.enterprise_edition.crud_helpers"
local rbac       = require "kong.rbac"
local workspaces = require "kong.workspaces"
local singletons = require "kong.singletons"
local admins     = require "kong.enterprise_edition.admins_helpers"
local ee_jwt     = require "kong.enterprise_edition.jwt"
local ee_api     = require "kong.enterprise_edition.api_helpers"
local ee_utils   = require "kong.enterprise_edition.utils"

local log = ngx.log
local ERR = ngx.ERR
local DEBUG = ngx.DEBUG
local time = ngx.time

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

  self.consumer.rbac_user = rbac_user
end


local function delete_rbac_user_roles(self, dao_factory, helpers)
  local roles, err = entity_relationships(dao_factory, self.consumer.rbac_user,
                                          "user", "role")
  if err then
    return helpers.yield_error(err)
  end

  local default_role

  for i = 1, #roles do
    dao_factory.rbac_user_roles:delete({
      user_id = self.consumer.rbac_user.id,
      role_id = roles[i].id,
    })

    if roles[i].name == self.consumer.rbac_user.name then
      default_role = roles[i]
    end
  end

  if default_role then
    local _, err = rbac.remove_user_from_default_role(self.consumer.rbac_user,
                                                      default_role)
    if err then
      helpers.yield_error(err)
    end
  end
end


return {
  ["/admins"] = {
    before = function(self, dao_factory, helpers)
      validate_auth_plugin(self, dao_factory, helpers)
      self.params.type = enums.CONSUMERS.TYPE.ADMIN
    end,

    GET = function(self, dao_factory)
      crud.paginated_set(self, dao_factory.consumers)
    end,

    POST = function(self, dao_factory, helpers)
      local _, msg, err = admins.validate(self.params, dao_factory, "POST")

      if err then
        log(ERR, _log_prefix, "failed to validate params: ", err)
        return helpers.responses.send_HTTP_INTERNAL_SERVER_ERROR()
      end

      if msg then
        log(ERR, _log_prefix, "failed to create admin: ", msg)
        return helpers.responses.send_HTTP_CONFLICT(
          "user already exists with same username, email, or custom_id"
        )
      end

      local ok, err = ee_utils.validate_email(self.params.email)
      if not ok then
        return helpers.responses.send_HTTP_BAD_REQUEST("Invalid email: " .. err)
      end

      crud.post({
        username  = self.params.username,
        custom_id = self.params.custom_id,
        type      = self.params.type,
        email     = self.params.email,
        status    = enums.CONSUMERS.STATUS.INVITED,
      }, dao_factory.consumers, function(consumer)
        local name = consumer.username or consumer.custom_id
        local rbac_user

        crud.post({
          name = name,
          user_token = utils.uuid(),
          comment = "User generated on creation of Admin.",
        }, dao_factory.rbac_users,
        function (new_rbac_user)
          rbac_user = new_rbac_user
          crud.post({
            consumer_id = consumer.id,
            user_id = new_rbac_user.id,
          }, dao_factory.consumers_rbac_users_map,
          function()
            local jwt
            -- only generate secrets for auth plugins with credentials tables
            if not self.token_optional then
              local token_ttl = singletons.configuration.admin_invitation_expiry

              -- Generate new secret
              local row, err = singletons.dao.consumer_reset_secrets:insert({
                consumer_id = consumer.id,
                client_addr = ngx.var.remote_addr,
              })

              if err then
                return helpers.yield_error(err)
              end

              local claims = {id = consumer.id, exp = time() + token_ttl}
              jwt, err = ee_jwt.generate_JWT(claims, row.secret)

              if err then
                return helpers.yield_error(err)
              end
            end

            if singletons.admin_emails then
              local _, err = singletons.admin_emails:invite({ consumer.email },
                                                            jwt)
                if err then
                  ngx.log(ngx.ERR, "[admins] error inviting user : ",
                          consumer.email)
                  return helpers.responses.send_HTTP_OK({
                    message = "User created, but error sending invitation email"
                              .. ":" .. consumer.email,
                    rbac_user = rbac_user,
                    consumer = consumer
                  })
                end
            else
              ngx.log(ngx.ERR, "[admins] error. There's no configuration "
                      .. "for email : ", consumer.email)
            end
              return helpers.responses.send_HTTP_OK({
                rbac_user = rbac_user,
                consumer = consumer
              })
            end)
            return helpers.responses.send_HTTP_INTERNAL_SERVER_ERROR(
              "Error creating admin (1)")
        end)
      end)

      return helpers.responses.send_HTTP_INTERNAL_SERVER_ERROR("Error "..
                                                           "creating admin (2)")
    end,
  },

  ["/admins/:username_or_id"] = {
    before = function(self, dao_factory, helpers)
      self.params.username_or_id = ngx.unescape_uri(self.params.username_or_id)
      crud.find_consumer_by_username_or_id(self, dao_factory, helpers)

      if self.consumer.type ~= enums.CONSUMERS.TYPE.ADMIN then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end
    end,

    GET = function(self, dao_factory, helpers)
      set_rbac_user(self, dao_factory, helpers)

      return helpers.responses.send_HTTP_OK(self.consumer)
    end,

    PATCH = function(self, dao_factory, helpers)
      local _, msg, err = admins.validate(self.params, dao_factory, "PATCH")

      if err then
        log(ERR, _log_prefix, "failed to validate params: ", err)
        return helpers.responses.send_HTTP_INTERNAL_SERVER_ERROR()
      end

      if msg then
        log(ERR, _log_prefix, "failed to update admin: ", msg)
        return helpers.responses.send_HTTP_CONFLICT()
      end

      crud.patch(self.params, dao_factory.consumers, self.consumer)
    end,

    DELETE = function(self, dao_factory, helpers)
      set_rbac_user(self, dao_factory, helpers)

      delete_rbac_user_roles(self, dao_factory, helpers)
      ee_crud.delete_without_sending_response(self.consumer.rbac_user,
                                              dao_factory.rbac_users)
      crud.delete(self.consumer, dao_factory.consumers)
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

      local rows, err = dao_factory.consumers:run_with_ws_scope({},
                                    dao_factory.consumers.find_all,
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
