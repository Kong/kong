local enums      = require "kong.enterprise_edition.dao.enums"
local rbac       = require "kong.rbac"
local workspaces = require "kong.workspaces"
local singletons = require "kong.singletons"
local admins     = require "kong.enterprise_edition.admins_helpers"
local ee_api     = require "kong.enterprise_edition.api_helpers"
local endpoints  = require "kong.api.endpoints"
local tablex     = require "pl.tablex"
local secrets = require "kong.enterprise_edition.consumer_reset_secret_helpers"
local cjson = require "cjson"


local emails = singletons.admin_emails
local kong = kong

local log = ngx.log
local ERR = ngx.ERR

local _log_prefix = "[admins] "


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
  ["openid-connect"] = { name = "openid-connect" },
}


local function validate_auth_plugin(self, dao_factory, helpers, plugin_name)
  local gui_auth = singletons.configuration.admin_gui_auth
  plugin_name = plugin_name or gui_auth
  self.plugin = auth_plugins[plugin_name]
  if not self.plugin and gui_auth then
    return kong.response.exit(404, { message = "Not found" })
  end

  if self.plugin and self.plugin.dao then
    self.collection = dao_factory[self.plugin.dao]
  else
    self.token_optional = true
  end
end


return {
  ["/admins"] = {
    before = function(self, db, helpers, parent)
       validate_auth_plugin(self, db, helpers)
    end,

    GET = function(self, db, helpers, parent)
      local res, err = admins.find_all()

      if err then
        return endpoints.handle_error(err)
      end

      return kong.response.exit(res.code, res.body)
    end,

    POST = function(self, db, helpers, parent)
      local res, err = admins.create(self.params, {
        token_optional = self.token_optional,
        workspace = ngx.ctx.workspaces[1],
        remote_addr = ngx.var.remote_addr,
        db = db,
      })

      if err then
        return endpoints.handle_error(err)
      end

      return kong.response.exit(res.code, res.body)
    end,
  },

  ["/admins/:admins"] = {
    before = function(self, db, helpers, parent)
      local err

      self.admin, err = admins.find_by_username_or_id(
                               ngx.unescape_uri(self.params.admins), true)
      if err then
        return endpoints.handle_error(err)
      end

      if not self.admin then
        return kong.response.exit(404, { message = "Not found" })
      end
    end,

    GET = function(self, db, helpers, parent)
      local opts = { generate_register_url = self.params.generate_register_url }

      local res, err = admins.generate_token(self.admin, opts)
      if err then
        return endpoints.handle_error(err)
      end

      return kong.response.exit(res.code, res.body)
    end,

    PATCH = function(self, db, helpers, parent)
      local res, err = admins.update(self.params, self.admin, { db = db })
      if err then
        return endpoints.handle_error(err)
      end

      return kong.response.exit(res.code, res.body)
    end,

    DELETE = function(self, db, helpers, parent)
      local res, err = admins.delete(self.admin, { db = db })
      if err then
        return endpoints.handle_error(err)
      end

      return kong.response.exit(res.code, res.body)
    end
  },

  ["/admins/:admin/roles"] = {
    before = function(self, db, helpers, parent)
      local err

      local name_or_id = ngx.unescape_uri(self.params.admin)
      self.admin, err = admins.find_by_username_or_id(name_or_id, true)
      if err then
        return endpoints.handle_error(err)
      end

      if not self.admin then
        return kong.response.exit(404, { message = "Not found" })
      end
    end,

    GET = function(self, db, helpers, parent)
      local roles, err = rbac.get_user_roles(db, self.admin.rbac_user)

      if err then
        return endpoints.handle_error(err)
      end

      -- filter out default roles
      roles = tablex.filter(roles, function(role) return not role.is_default end)

      setmetatable(roles, cjson.empty_array_mt)

      return kong.response.exit(200, {
        roles = roles,
      })
    end,

    POST = function(self, db, helpers, parent)
      -- we have the user, now verify our roles
      if not self.params.roles then
        return kong.response.exit(400, { message = "must provide >= 1 role" })
      end

      local roles, err = rbac.objects_from_names(db, self.params.roles, "role")
      if err then
        if err:find("not found with name", nil, true) then
          return kong.response.exit(400, { message = err })
        else
          return endpoints.handle_error(err)
        end
      end

      -- we've now validated that all our roles exist, and this user exists,
      -- so time to create the assignment
      for i = 1, #roles do
        local _, _, err_t = db.rbac_user_roles:insert({
          user = self.admin.rbac_user,
          role = roles[i]
        })

        if err_t then
          return endpoints.handle_error(err_t)
        end
      end

      -- invalidate rbac user so we don't fetch the old roles
      local cache_key = db["rbac_user_roles"]:cache_key(self.admin.rbac_user.id)
      singletons.cache:invalidate(cache_key)

      -- re-fetch the users roles so we show all the role objects, not just our
      -- newly assigned mappings
      roles, err = rbac.get_user_roles(db, self.admin.rbac_user)
      if err then
        return endpoints.handle_error(err)
      end

      -- filter out default roles
      roles = tablex.filter(roles, function(role) return not role.is_default end)

      return kong.response.exit(201, { roles = roles })
    end,

    DELETE = function(self, db, helpers, parent)
      -- we have the user, now verify our roles
      if not self.params.roles then
        return kong.response.exit(400, { message = "must provide >= 1 role" })
      end

      local roles, err = rbac.objects_from_names(db, self.params.roles, "role")
      if err then
        if err:find("not found with name", nil, true) then
          return kong.response.exit(400, { message = err })
        else
          return endpoints.handle_error(err)
        end
      end

      local _
      for i = 1, #roles do
        _, err = db.rbac_user_roles:delete({
          user = self.admin.rbac_user,
          role = roles[i],
        })
        if err then
          return endpoints.handle_error(err)
        end
      end

      local cache_key = db.rbac_user_roles:cache_key(self.admin.rbac_user.id)
      singletons.cache:invalidate(cache_key)

      return kong.response.exit(204)
    end,
  },

  ["/admins/password_resets"] = {
    before = function(self, db, helpers, parent)
      validate_auth_plugin(self, db, helpers)

      -- if we don't store your creds, you don't belong here
      if self.token_optional then
        return kong.response.exit(404, { message = "Not found" })
      end

      if not self.params.email or self.params.email == "" then
        return kong.response.exit(400, { message = "email is required" })
      end

      -- if you've forgotten your password, this is all we know about you
      self.admin = admins.find_by_email(self.params.email)
      if not self.admin then
        return kong.response.exit(404, { message = "Not found" })
      end

      -- when you reset your password, you come in with an email and a JWT
      -- if it's there, make sure it's good
      if self.params.token then
        -- validate_jwt both validates the JWT and determines which consumer
        -- owns it, setting consumer_id on self. still :magic:
        ee_api.validate_jwt(self, db, helpers)

        -- make sure the email in the query params matches the one in the token
        if self.admin.consumer.id ~= self.consumer_id then
          return kong.response.exit(404, { message = "Not found" })
        end
      end
    end,

    -- create a password reset request and send mail
    POST = function(self, db, helpers, parent)
      local expiry = kong.configuration.admin_invitation_expiry

      local jwt, err = secrets.create(self.admin.consumer, ngx.var.remote_addr, expiry)

      if err then
        return endpoints.handle_error("failed to generate reset token: " .. err)
      end

      -- send mail
      local _, err = emails:reset_password(self.admin.email, jwt)
      if err then
        return endpoints.handle_error(err)
      end

      return kong.response.exit(201)
    end,

    -- reset password and consume token
    PATCH = function(self, db, helpers, parent)
      local new_password = self.params.password
      if not new_password or new_password == "" then
        return kong.response.exit(400, { message = "password is required" })
      end

      local found, err = admins.reset_password(self.plugin,
                                               self.collection,
                                               self.admin.consumer,
                                               new_password,
                                               self.reset_secret_id)

      if err then
        return endpoints.handle_error(err)
      end

      if not found then
        return kong.response.exit(404, { message = "Not found" })
      end

      local _, err = emails:reset_password_success(self.admin.email)
      if err then
        return endpoints.handle_error(err)
      end

      return kong.response.exit(200)
    end
  },

  ["/admins/:admin/workspaces"] = {
    GET = function(self, db, helpers, parent)
      -- lookup across all workspaces
      local res, err = workspaces.run_with_ws_scope({},
                                                    admins.workspaces_for_admin,
                                                    self.params.admin)
      if err then
        return endpoints.handle_error(err)
      end

      return kong.response.exit(res.code, res.body)
    end
  },

  ["/admins/register"] = {
    before = function(self, db, helpers, parent)
      validate_auth_plugin(self, db, helpers)
      if self.token_optional then
        return kong.response.exit(400, {
          message = "cannot register with admin_gui_auth = " .. self.plugin.name})
      end
      ee_api.validate_email(self, db, helpers)
      ee_api.validate_jwt(self, db, helpers)
    end,

    POST = function(self, db, helpers, parent)
      -- validate_jwt both validates the JWT and determines which consumer
      -- owns it, setting that on self. :magic:
      if not self.consumer_id then
        log(ERR, _log_prefix, "consumer not found for registration")
        return kong.response.exit(401, { message = "Unauthorized" })
      end

      -- this block is a little messy. A consumer cannot logically belong to
      -- >1 admin, but the schema doesn't generate select_by for foreign keys.
      -- could also use `select_all` here, but for now prefer to use CE
      -- functions where possible.
      local res = {}
      for row, err in db.admins:each_for_consumer({ id = self.consumer_id }) do
        if err then
          return endpoints.handle_error(err)
        end
        res[1] = row
      end

      local admin = res[1]

      if not admin or admin.email ~= self.params.email then
        return kong.response.exit(401, { message = "Unauthorized" })
      end

      local credential_data
      local credential_dao

      -- create credential object based on admin_gui_auth
      if self.plugin.name == "basic-auth" then
        credential_dao = db.basicauth_credentials
        credential_data = {
          consumer = admin.consumer,
          username = admin.username,
          password = self.params.password,
        }
      end

      if self.plugin.name == "key-auth" then
        credential_dao = db.keyauth_credentials
        credential_data = {
          consumer = admin.consumer,
          key = self.params.password,
        }
      end

      if not credential_data then
        return kong.response.exit(400,
          "Cannot create credential with admin_gui_auth = " ..
          self.plugin.name)
      end

      -- Find the workspace the consumer is in
      local refs, err = db.workspace_entities:select_all({
        entity_type = "consumers",
        entity_id = admin.consumer.id,
        unique_field_name = "id",
      })

      if err then
        return endpoints.handle_error(err)
      end

      -- Set the current workspace so the credential is created there
      local consumer_ws = {
        id = refs[1].workspace_id,
        name = refs[1].workspace_name,
      }

      local _, err = workspaces.run_with_ws_scope(
                                { consumer_ws },
                                credential_dao.insert,
                                credential_dao,
                                credential_data)
      if err then
        return endpoints.handle_error(err)
      end

      if admin.status == enums.CONSUMERS.STATUS.INVITED then
        db.admins:update({status = enums.CONSUMERS.STATUS.APPROVED}, {id = admin.id})
      end

      -- Mark the token secret as consumed
      local _, err = secrets.consume_secret(self.reset_secret_id)
      if err then
        return endpoints.handle_error(err)
      end

      return kong.response.exit(201)
    end,
  },

  ["/admins/self/password"] = {
    before = function(self, db, helpers, parent)
      validate_auth_plugin(self, db, helpers)

      if not self.admin then
        return kong.response.exit(404, {message = "Not found"})
      end
    end,

    PATCH = function(self, db, helpers, parent)
      local res, err = admins.update_password(self.admin, self.params)

      if err then
        return endpoints.handle_error(err)
      end

      return kong.response.exit(res.code, res.body)
    end
  },

  ["/admins/self/token"] = {
    before = function(self, db, helpers, parent)
      validate_auth_plugin(self, db, helpers)
      if not self.admin then
        return kong.response.exit(404, {message = "Not found"})
      end
    end,

    PATCH = function(self, db, helpers, parent)
      local res, err = admins.update_token(self.admin, self.params)
      if err then
        return endpoints.handle_error(err)
      end

      return kong.response.exit(res.code, res.body)
    end
  }
}
