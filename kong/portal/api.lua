-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson         = require "cjson.safe"
local constants     = require "kong.constants"
local auth          = require "kong.portal.auth"
local workspaces    = require "kong.workspaces"
local portal_smtp_client = require "kong.portal.emails"
local endpoints          = require "kong.api.endpoints"
local crud_helpers       = require "kong.portal.crud_helpers"
local enums              = require "kong.enterprise_edition.dao.enums"
local ee_api             = require "kong.enterprise_edition.api_helpers"
local auth_helpers       = require "kong.enterprise_edition.auth_helpers"
local secrets            = require "kong.enterprise_edition.consumer_reset_secret_helpers"
local dao_helpers        = require "kong.portal.dao_helpers"
local workspace_config = require "kong.portal.workspace_config"
local kong = kong


local PORTAL_DEVELOPER_META_FIELDS = constants.WORKSPACE_CONFIG.PORTAL_DEVELOPER_META_FIELDS
local PORTAL_AUTH = constants.WORKSPACE_CONFIG.PORTAL_AUTH
local PORTAL_AUTO_APPROVE = constants.WORKSPACE_CONFIG.PORTAL_AUTO_APPROVE
local PORTAL_TOKEN_EXP = constants.WORKSPACE_CONFIG.PORTAL_TOKEN_EXP

--- Allowed auth plugins
-- Table containing allowed auth plugins that the developer portal api
-- can create credentials for.
--
--["<route>"]:     {  name = "<name>",    dao = "<dao_collection>" }
local auth_plugins = {
  ["basic-auth"] = { name = "basic-auth", dao = "basicauth_credentials", credential_key = "password" },
  ["oauth2"] =     { name = "oauth2",     dao = "oauth2_credentials" },
  ["hmac-auth"] =  { name = "hmac-auth",  dao = "hmacauth_credentials" },
  ["jwt"] =        { name = "jwt",        dao = "jwt_secrets" },
  ["key-auth"] =   { name = "key-auth",   dao = "keyauth_credentials", credential_key = "key" },
  ["openid-connect"] = { name = "openid-connect" },
}


local function get_workspace()
  return workspaces.get_workspace()
end


local function validate_credential_plugin(self, db, helpers)
  local plugin_name = ngx.unescape_uri(self.params.plugin)
  self.credential_plugin = auth_plugins[plugin_name]
  if not self.credential_plugin then
    return kong.response.exit(404, { message = "Not found" })
  end

  self.credential_collection = db.daos[self.credential_plugin.dao]
end


local function handle_vitals_response(res, err, helpers)
  if err then
    if err:find("Invalid query params", nil, true) then
      return kong.response.exit(400, { message = err })
    end

    return endpoints.handle_error({ message = err })
  end

  return kong.response.exit(200, res)
end

return {
  ["/auth"] = {
    GET = function(self, db, helpers)
      auth.login(self, db, helpers)
      return kong.response.exit(200)
    end,

    DELETE = function(self, db, helpers)
      auth.authenticate_api_session(self, db, helpers)
      return kong.response.exit(200)
    end,
  },

  ["/files/unauthenticated"] = {
    -- List all unauthenticated files stored in the portal file system
    GET = function(self, db, helpers)
      local files = {}
      for file, err in db.files:each(nil, { skip_rbac = true }) do
        if err then
          return endpoints.handle_error(err)
        end

        if file.auth == false and (self.params.type == nil or file.type == self.params.type) then
          table.insert(files, file)
        end
      end

      local paginated_results, _, err_t = crud_helpers.paginate(self, files)
      if not paginated_results then
        return endpoints.handle_error(err_t)
      end

      return kong.response.exit(200, paginated_results)
    end,
  },

  ["/files"] = {
    before = function(self, db, helpers)
      local ws = get_workspace()
      local portal_auth = workspace_config.retrieve(PORTAL_AUTH, ws)
      if portal_auth and portal_auth ~= "" then
        auth.authenticate_api_session(self, db, helpers)
      end
    end,

    GET = function(self, db, helpers)
      local files = {}
      for file, err in db.files:each(nil, { skip_rbac = true }) do
        if err then
          return endpoints.handle_error(err)
        end

        if self.params.type == nil or file.type == self.params.type then
          table.insert(files, file)
        end
      end

      local paginated_results, _, err_t = crud_helpers.paginate(self, files)
      if not paginated_results then
        return endpoints.handle_error(err_t)
      end

      return kong.response.exit(200, paginated_results)
    end,
  },

  ["/files/*"] = {
    before = function(self, db, helpers)
      local ws = get_workspace()
      local portal_auth = workspace_config.retrieve(PORTAL_AUTH, ws)
      if portal_auth and portal_auth ~= "" then
        auth.authenticate_api_session(self, db, helpers)
      end
    end,

    GET = function(self, db, helpers)
      local identifier = self.params.splat

      local file, err, err_t = db.files:select_by_name(identifier, { skip_rbac = true })
      if err then
        return endpoints.handle_error(err_t)
      end

      return kong.response.exit(200, {data = file})
    end,
  },

  ["/register"] = {
    POST = function(self, db, helpers)
      if self.params.status then
        return kong.response.exit(400, {
          fields = { status = "invalid field" },
        })
      end

      local password = self.params and self.params.password
      local ok, _, err_t = dao_helpers.validate_developer_password(password)
      if not ok then
        return endpoints.handle_error(err_t)
      end

      local developer, _, err_t = db.developers:insert(self.params)
      if not developer then
        return endpoints.handle_error(err_t)
      end

      local name_or_email = dao_helpers.get_name_or_email(developer)

      local res = {
        developer = developer,
      }

      if developer.status == enums.CONSUMERS.STATUS.PENDING then
        local portal_emails = portal_smtp_client.new()
        -- if name does not exist, we use the email for email template
        local _, err = portal_emails:access_request(developer.email,
                                                    name_or_email)
        if err then
          if err.code then
            return kong.response.exit(err.code, { message = err.message })
          end

          return endpoints.handle_error(err)
        end
      end

      if developer.status == enums.CONSUMERS.STATUS.UNVERIFIED and
         kong.configuration.portal_email_verification then

        local workspace = workspaces.get_workspace()
        local token_ttl = workspace_config.retrieve(PORTAL_TOKEN_EXP, workspace)
        local jwt, err = secrets.create(developer.consumer, ngx.var.remote_addr, token_ttl)
        if not jwt then
          return endpoints.handle_error(err)
        end

        -- Email user with reset jwt included
        local portal_emails = portal_smtp_client.new()
        local _, err = portal_emails:account_verification_email(developer.email,
                                                                jwt, name_or_email)
        if err then
          return endpoints.handle_error(err)
        end
      end

      return kong.response.exit(200, res)
    end,
  },

  ["/verify-account"] = {
    POST = function(self, db, helpers)
      if not kong.configuration.portal_email_verification then
        return kong.response.exit(404)
      end

      auth.validate_auth_plugin(self, db, helpers)
      ee_api.validate_jwt(self, db, helpers)

      local consumer, _, err_t = db.consumers:select({ id = self.consumer_id },
                                                          { skip_rbac = true })
      if err_t then
        return endpoints.handle_error(err_t)
      end

      if not consumer then
        return kong.response.exit(204, { message = "Not found" })
      end

      local developer = db.developers:select_by_email(consumer.username)
      if not developer then
        return kong.response.exit(204)
      end

      if developer.status ~= enums.CONSUMERS.STATUS.UNVERIFIED then
        return kong.response.exit(204)
      end

      local workspace = get_workspace()
      local auto_approve = workspace_config.retrieve(PORTAL_AUTO_APPROVE, workspace)

      local status = enums.CONSUMERS.STATUS.PENDING
      if auto_approve then
        status = enums.CONSUMERS.STATUS.APPROVED
      end

      local ok, _, err_t = db.developers:update_by_email(consumer.username, {
        status = status
      })

      if not ok then
        return endpoints.handle_error(err_t)
      end

      local name_or_email = dao_helpers.get_name_or_email(developer)

      -- Mark the token secret as consumed
      local ok, err = secrets.consume_secret(self.reset_secret_id)
      if not ok then
        return endpoints.handle_error(err)
      end

      -- Email user with reset success confirmation
      local portal_emails = portal_smtp_client.new()

      local err
      if auto_approve then
        _, err = portal_emails:account_verification_success_approved(developer.email, name_or_email)
        if err then
          if err.code then
            return kong.response.exit(err.code, { message = err.message })
          end

          return endpoints.handle_error(err)
        end

      else
        _, err = portal_emails:access_request(developer.email, name_or_email)
        if err then
          if err.code then
            return kong.response.exit(err.code, { message = err.message })
          end

          return endpoints.handle_error(err)
        end

        _, err = portal_emails:account_verification_success_pending(developer.email, name_or_email)
        if err then
          if err.code then
            return kong.response.exit(err.code, { message = err.message })
          end

          return endpoints.handle_error(err)
        end
      end

      if err then
        return endpoints.handle_error(err)
      end

      return kong.response.exit(200, { status = status })
    end,
  },

  ["/resend-account-verification"] = {
    POST = function(self, db, helpers)
      if not kong.configuration.portal_email_verification then
        return kong.response.exit(404)
      end

      if not self.params.email then
        return kong.response.exit(400, { message = "Email is required" })
      end

      local consumer, _, err_t = db.consumers:select_by_username(self.params.email,
                                                                 { skip_rbac = true })
      if err_t then
        return endpoints.handle_error(err_t)
      end

      if not consumer then
        return kong.response.exit(204)
      end

      local developer, _, err_t = db.developers:select_by_email(consumer.username)
      if err_t then
        return endpoints.handle_error(err_t)
      end

      if not developer then
        return kong.response.exit(204)
      end

      if developer.status ~= enums.CONSUMERS.STATUS.UNVERIFIED then
        return kong.response.exit(204)
      end

      local name_or_email = dao_helpers.get_name_or_email(developer)

      -- -- Invalidate pending account verifications
      local ok, err = secrets.invalidate_pending_resets(consumer)
      if not ok then
        return endpoints.handle_error(err)
      end

      local workspace = workspaces.get_workspace()
      local token_ttl = workspace_config.retrieve(PORTAL_TOKEN_EXP, workspace)
      local jwt, err = secrets.create(developer.consumer, ngx.var.remote_addr, token_ttl)
      if not jwt then
        return endpoints.handle_error(err)
      end

      local portal_emails = portal_smtp_client.new()
      local _, err = portal_emails:account_verification_email(developer.email, jwt, name_or_email)
      if err then
        if err.code then
          return kong.response.exit(err.code, { message = err.message })
        end

        return endpoints.handle_error(err)
      end

      return kong.response.exit(204)
    end,
  },

  ["/invalidate-account-verification"] = {
    POST = function(self, db, helpers)
      if not kong.configuration.portal_email_verification then
        return kong.response.exit(404)
      end

      auth.validate_auth_plugin(self, db, helpers)
      ee_api.validate_jwt(self, db, helpers)

      local consumer, _, err_t = db.consumers:select({ id = self.consumer_id },
                                                          { skip_rbac = true })
      if err_t then
        return endpoints.handle_error(err_t)
      end

      if not consumer then
        return kong.response.exit(404, { message = "Not found" })
      end

      local developer, _, err_t = db.developers:select_by_email(consumer.username)
      if err_t then
        return endpoints.handle_error(err_t)
      end

      if not developer then
        return kong.response.exit(204)
      end

      if developer.status ~= enums.CONSUMERS.STATUS.UNVERIFIED then
        return kong.response.exit(204)
      end

      -- Invalidate pending account verifications
      local ok, err = secrets.invalidate_pending_resets(consumer)
      if not ok then
        return endpoints.handle_error(err)
      end

      local ok, _, err_t = db.developers:delete({ id = developer.id })
      if not ok then
        return endpoints.handle_error(err_t)
      end

      return kong.response.exit(204)
    end,
  },

  ["/validate-reset"] = {
    POST = function(self, db, helpers)
      auth.validate_auth_plugin(self, db, helpers)
      ee_api.validate_jwt(self, db, helpers)
      return kong.response.exit(200)
    end,
  },

  ["/reset-password"] = {
    POST = function(self, db, helpers)
      auth.validate_auth_plugin(self, db, helpers)
      ee_api.validate_jwt(self, db, helpers)


      -- If we made it this far, the jwt is valid format and properly signed.
      -- Now we will lookup the consumer and credentials we need to update
      -- Lookup consumer by id contained in jwt, if not found, this will 404


      local consumer, _, err_t = db.consumers:select({ id = self.consumer_id },
                                                          { skip_rbac = true })
      if err_t then
        return endpoints.handle_error(err_t)
      end

      if not consumer then
        return kong.response.exit(404, { message = "Not found" })
      end

      local credential
      for row, err in db.credentials:each_for_consumer({ id = consumer.id }) do
        if err then
          return endpoints.handle_error(err)
        end

        if row.consumer_type == enums.CONSUMERS.TYPE.DEVELOPER and
           row.plugin == self.plugin.name then
           credential = row
        end
      end

      if not credential then
        return kong.response.exit(404, { message = "Not found" })
      end

      -- key or password
      local new_password = self.params[self.plugin.credential_key]
      if not new_password or new_password == "" then
        return kong.response.exit(400,
          { message = self.plugin.credential_key .. " is required"})
      end

      local ok, _, err_t = dao_helpers.validate_developer_password(new_password)
      if not ok then
        return endpoints.handle_error(err_t)
      end

      local cred_pk = { id = credential.id }
      local entity = {
        consumer = { id = consumer.id },
        [self.plugin.credential_key] = new_password,
      }
      local ok, err = crud_helpers.update_login_credential(
                                              self.collection, cred_pk, entity)
      if err then
        return endpoints.handle_error(err)
      end

      if not ok then
        return kong.response.exit(404, { message = "Not found" })
      end

      -- Mark the token secret as consumed
      local ok, err = secrets.consume_secret(self.reset_secret_id)
      if not ok then
        return endpoints.handle_error(err)
      end

      auth_helpers.reset_attempts(consumer)

      local developer, _, err_t = db.developers:select_by_email(consumer.username)
      if err_t then
        return endpoints.handle_error(err_t)
      end

      local name_or_email = dao_helpers.get_name_or_email(developer)

      -- Email user with reset success confirmation
      local portal_emails = portal_smtp_client.new()
      local _, err = portal_emails:password_reset_success(consumer.username, name_or_email)
      if err then
        if err.code then
          return kong.response.exit(err.code, { message = err.message })
        end

        return endpoints.handle_error(err)
      end

      return kong.response.exit(200)
    end,
  },

  ["/forgot-password"] = {
    POST = function(self, db, helpers)
      auth.validate_auth_plugin(self, db, helpers)

      local workspace = get_workspace()
      local token_ttl = workspace_config.retrieve(PORTAL_TOKEN_EXP,
                                                     workspace)

      local developer, _, err_t = db.developers:select_by_email(
                                    self.params.email, { skip_rbac = true })
      if err_t then
        return endpoints.handle_error(err_t)
      end

      -- If we do not have a developer, return 200 ok
      if not developer then
        return kong.response.exit(200)
      end

      -- Generate a reset secret and jwt
      local jwt, err = secrets.create(developer.consumer, ngx.var.remote_addr,
                                      token_ttl)
      if not jwt then
        return endpoints.handle_error(err)
      end

      local name_or_email = dao_helpers.get_name_or_email(developer)

      -- Email user with reset jwt included
      local portal_emails = portal_smtp_client.new()
      local _, err = portal_emails:password_reset(developer.email, jwt, name_or_email)
      if err then
        if err.code then
          return kong.response.exit(err.code, { message = err.message })
        end

        return endpoints.handle_error(err)
      end

      return kong.response.exit(200)
    end,
  },

  ["/config"] = {
    before = function(self, db, helpers)
      auth.authenticate_api_session(self, db, helpers)
    end,

    GET = function(self, db, helpers)
      local distinct_plugins = {}

      do
        local rows = {}
        for row, err in db.plugins:each() do
          if err then
            return kong.response.exit(500, { message = "An unexpected error occurred" })
          end

          table.insert(rows, row)
        end

        local map = {}
        for _, row in ipairs(rows) do
          if not map[row.name] and auth_plugins[row.name] and auth_plugins[row.name].dao then
            distinct_plugins[#distinct_plugins+1] = row.name
          end
          map[row.name] = true
        end
      end

      return kong.response.exit(200, {
        plugins = {
          enabled_in_cluster = distinct_plugins,
        }
      })
    end,
  },

  ["/developer"] = {
    before = function(self, db, helpers)
      auth.authenticate_api_session(self, db, helpers)
    end,

    GET = function(self, db, helpers)
      return kong.response.exit(200, self.developer)
    end,

    DELETE = function(self, db, helpers)
      local ok, err = db.developers:delete({id = self.developer.id})
      if not ok then
        if err then
          return endpoints.handle_error(err)
        else
          return kong.response.exit(404, { message = "Not found" })
        end
      end

      return kong.response.exit(204)
    end
  },

  ["/session"] = {
    before = function(self, db, helpers)
      auth.authenticate_api_session(self, db, helpers)
    end,
    GET = function(self, dao, helpers)
      local user_session = kong.ctx.shared.authenticated_session
      if not user_session then
        return endpoints.handle_error('could not find session')
      end

      local idling_timeout = user_session.idling_timeout
      local rolling_timeout = user_session.rolling_timeout
      local absolute_timeout = user_session.absolute_timeout
      local stale_ttl = user_session.stale_ttl
      local expires_in = user_session:get_property("timeout")
      local expires = ngx.time() + expires_in

      return kong.response.exit(200, {
        session = {
          idling_timeout = idling_timeout,
          rolling_timeout = rolling_timeout,
          absolute_timeout = absolute_timeout,
          stale_ttl = stale_ttl,
          expires_in = expires_in,
          expires = expires, -- unix timestamp seconds
          -- TODO: below should be removed, kept for backward compatibility:
          cookie = {
            discard = stale_ttl,
            renew = rolling_timeout - math.floor(rolling_timeout * 0.75),
            -- see: https://github.com/bungle/lua-resty-session/blob/v4.0.0/lib/resty/session.lua#L1999
            idletime = idling_timeout,
            lifetime = rolling_timeout,
          },
        }
      })
    end,
  },

  ["/developer/meta_fields"] = {
    before = function(self, dao_factory, helpers)
      crud_helpers.exit_if_portal_disabled()
    end,

    GET = function(self, dao_factory, helpers)
      local workspace = get_workspace()
      local developer_extra_fields = workspace_config.retrieve(PORTAL_DEVELOPER_META_FIELDS, workspace)
      return kong.response.exit(200, developer_extra_fields)
    end,
  },

  ["/developer/password"] = {
    before = function(self, db, helpers)
      auth.authenticate_api_session(self, db, helpers)
    end,

    PATCH = function(self, db, helpers)
      local credential
      for row, err in db.credentials:each_for_consumer({ id = self.developer.consumer.id}) do
        if err then
          return endpoints.handle_error(err)
        end

        if row.consumer_type == enums.CONSUMERS.TYPE.DEVELOPER and
           row.plugin == self.plugin.name then
           credential = row
        end
      end

      if not credential then
        return kong.response.exit(404, { message = "Not found" })
      end

      local cred_params = {}

      cred_params.consumer = { id = self.developer.consumer.id }

      if self.params.password then
        -- creds here is redudent, and should replace credential from above,
        -- this can be done when removing key auth
        local creds, bad_req_message, err = auth_helpers.verify_password(self.developer, self.params.old_password,
        self.params.password)

        if not creds then
          if err then
            return endpoints.handle_error(err)
          end

          if bad_req_message then
            return kong.response.exit(400, { message = bad_req_message })
          end
        end

        cred_params.password = self.params.password
        self.params.password = nil


      elseif self.params.key then
        cred_params.key = self.params.key
        self.params.key = nil
      else
        return kong.response.exit(400, { message = "key or password is required" })
      end

      local ok, _, err_t = dao_helpers.validate_developer_password(cred_params.password)
      if not ok then
        return endpoints.handle_error(err_t)
      end

      local cred_pk = { id = credential.id }
      local ok, err = crud_helpers.update_login_credential(self.collection,
                                                          cred_pk, cred_params)
      if err then
        return endpoints.handle_error(err)
      end

      if not ok then
        return kong.response.exit(404, { message = "Not found" })
      end

      return kong.response.exit(204)
    end,
  },

  ["/developer/email"] = {
    before = function(self, db, helpers)
      auth.authenticate_api_session(self, db, helpers)
    end,

    PATCH = function(self, db, helpers)
      local developer, _, err_t = db.developers:update({
        id = self.developer.id
      }, {
        email = self.params.email
      })

      if not developer then
        return endpoints.handle_error(err_t)
      end

      return kong.response.exit(200, developer)
    end,
  },

  ["/developer/meta"] = {
    before = function(self, db, helpers)
      auth.authenticate_api_session(self, db, helpers)
    end,

    -- PUT is used by portal gui to avoid issues with validation after schema change
    PUT = function(self, db, helpers)
      local meta_params = self.params.meta and cjson.decode(self.params.meta)

      if not meta_params then
        return kong.response.exit(400, { message = "meta required" })
      end

      local developer, _, err = db.developers:update({
        id = self.developer.id
      }, {
        meta = cjson.encode(meta_params)
      })

      if err then
        return endpoints.handle_error(err)
      end

      if not developer then
        return kong.response.exit(404, { message = "Not found" })
      end

      return kong.response.exit(200)
    end,
  },

  ["/application_services"] = {
    before = function(self, db, helpers)
      auth.authenticate_api_session(self, db, helpers)
    end,

    GET = function(self, db, helpers)
      return crud_helpers.get_application_services(self, db, helpers)
    end,
  },

  ["/applications"] = {
    before = function(self, db, helpers)
      auth.authenticate_api_session(self, db, helpers)
    end,

    GET = function(self, db, helpers)
      local include_instances = self.req.params_get and self.req.params_get.include_instances == "true"

      return crud_helpers.get_applications(self, db, helpers, include_instances)
    end,

    POST = function(self, db, helpers)
      self.params.developer = { id = self.developer.id }
      local application, _, err_t = kong.db.applications:insert(self.params)
      if err_t then
        return endpoints.handle_error(err_t)
      end

      return kong.response.exit(200, application)
    end,
  },

  ["/applications/:applications"] = {
    before = function(self, db, helpers)
      auth.authenticate_api_session(self, db, helpers)

      local application_pk = self.params.applications
      self.params.applications = nil

      local application, _, err_t = db.applications:select({ id = application_pk })
      if err_t then
        return endpoints.handle_error(err_t)
      end

      if not application or self.developer.id ~= application.developer.id then
        return kong.response.exit(404, { message = "Not found" })
      end

      self.application = application
    end,

    GET = function(self, db, helpers)
      return kong.response.exit(200, self.application)
    end,

    PATCH = function(self, db, helpers)
      local updates = self.params and {
        custom_id = self.params.custom_id,
        description = self.params.description,
        meta = self.params.meta,
        name = self.params.name,
        redirect_uri = self.params.redirect_uri,
      } or {}

      local application, _, err_t = db.applications:update({ id = self.application.id }, updates)
      if err_t then
        return endpoints.handle_error(err_t)
      end

      return kong.response.exit(200, application)
    end,

    DELETE = function(self, db, helpers)
      local ok, _, err_t = db.applications:delete({ id = self.application.id })
      if not ok then
        return endpoints.handle_error(err_t)
      end

      return kong.response.exit(204)
    end,
  },

  ["/applications/:applications/application_instances"] = {
    before = function(self, db, helpers)
      auth.authenticate_api_session(self, db, helpers)

      local application_pk = self.params.applications
      self.params.applications = nil

      local application, _, err_t = db.applications:select({ id = application_pk })
      if err_t then
        return endpoints.handle_error(err_t)
      end

      if not application or self.developer.id ~= application.developer.id then
        return kong.response.exit(404, { message = "Not found" })
      end

      self.application = application
      self.consumer = { id = self.application.consumer.id }
    end,

    POST = function(self, db, helpers)
      if not self.params.service or not self.params.service.id then
        return kong.response.exit(400, { message = "service.id required"})
      end

      self.params.status = nil
      return crud_helpers.create_application_instance(self, db, helpers)
    end,

    GET = function(self, db, helpers)
      return crud_helpers.get_application_instances_by_application(self, db, helpers)
    end,
  },

  ["/applications/:applications/application_instances/:application_instances"] = {
    before = function(self, db, helpers)
      auth.authenticate_api_session(self, db, helpers)

      local application_pk = self.params.applications
      self.params.applications = nil

      local application, _, err_t = db.applications:select({ id = application_pk })
      if err_t then
        return endpoints.handle_error(err_t)
      end

      if not application or self.developer.id ~= application.developer.id then
        return kong.response.exit(404, { message = "Not found" })
      end

      self.application = application

      local application_instance_pk = self.params.application_instances
      self.params.application_instances = nil

      local application_instance, _, err_t = db.application_instances:select({ id = application_instance_pk })
      if err_t then
        return endpoints.handle_error(err_t)
      end

      if not application_instance or application_instance.application.id ~= application.id then
        return kong.response.exit(404, { message = "Not found" })
      end

      self.application_instance = application_instance
    end,

    GET = function(self, db, helpers)
      return kong.response.exit(200, self.application_instance)
    end,

    PATCH = function(self, db, helpers)
      return crud_helpers.update_application_instance(self, db, helpers)
    end,

    DELETE = function(self, db, helpers)
      return crud_helpers.delete_application_instance(self, db, helpers)
    end,
  },

  ["/applications/:applications/credentials"] = {
    before = function(self, db, helpers)
      auth.authenticate_api_session(self, db, helpers)
      crud_helpers.exit_if_external_oauth2()

      local application_pk = self.params.applications
      self.params.applications = nil

      local application, _, err_t = db.applications:select({ id = application_pk })
      if err_t then
        return endpoints.handle_error(err_t)
      end

      if not application or self.developer.id ~= application.developer.id then
        return kong.response.exit(404, { message = "Not found" })
      end

      self.application = application
    end,

    GET = function(self, db, helpers)
      self.credential_collection = db.daos["oauth2_credentials"]
      self.consumer = { id = self.application.consumer.id }

      return crud_helpers.get_credentials(self, db, helpers)
    end,

    POST = function(self, db, helpers)
      return crud_helpers.create_app_reg_credentials(self, db, helpers)
    end,
  },

  ["/applications/:applications/credentials/:credential_id"] = {
    before = function(self, db, helpers)
      auth.authenticate_api_session(self, db, helpers)
      crud_helpers.exit_if_external_oauth2()

      local application_pk = self.params.applications
      self.params.applications = nil

      local application, _, err_t = db.applications:select({ id = application_pk })
      if err_t then
        return endpoints.handle_error(err_t)
      end

      if not application or self.developer.id ~= application.developer.id then
        return kong.response.exit(404, { message = "Not found"})
      end

      self.consumer = application.consumer
    end,

    GET = function(self, db, helpers)
      self.credential_collection = db.daos["oauth2_credentials"]
      return crud_helpers.get_credential(self, db, helpers)
    end,

    -- PATCH not allowed, user can only DELETE and POST app credentials
    PATCH = function(self, db, helpers)
      return kong.response.exit(405)
    end,

    DELETE = function(self, db, helpers)
      return crud_helpers.delete_app_reg_credentials(self, db, helpers)
    end,
  },

  ["/credentials/:plugin"] = {
    before = function(self, db, helpers)
      auth.authenticate_api_session(self, db, helpers)
      validate_credential_plugin(self, db, helpers)
    end,

    GET = function(self, db, helpers)
      self.consumer = { id = self.developer.consumer.id }
      return crud_helpers.get_credentials(self, db, helpers)
    end,

    POST = function(self, db, helpers)
      self.params.consumer = { id = self.developer.consumer.id }
      return crud_helpers.create_credential(self, db, helpers, { skip_rbac = true })
    end,
  },

  ["/credentials/:plugin/:credential_id"] = {
    before = function(self, db, helpers)
      auth.authenticate_api_session(self, db, helpers)
      validate_credential_plugin(self, db, helpers)
    end,

    GET = function(self, db, helpers)
      self.consumer = { id = self.developer.consumer.id }
      return crud_helpers.get_credential(self, db, helpers, { skip_rbac = true })
    end,

    PATCH = function(self, db, helpers)
      self.consumer = { id = self.developer.consumer.id }
      return crud_helpers.update_credential(self, db, helpers, { skip_rbac = true })
    end,

    DELETE = function(self, db, helpers)
      self.consumer = { id = self.developer.consumer.id }
      return crud_helpers.delete_credential(self, db, helpers, { skip_rbac = true })
    end,
  },

  ["/vitals/status_codes/by_consumer"] = {
    before = function(self, db, helpers)
      auth.authenticate_api_session(self, db, helpers)
      if not kong.configuration.vitals then
        return kong.response.exit(404, { message = "Not found" })
      end
    end,

    GET = function(self, db, helpers)
      local opts = {
        entity_type = "consumer",
        duration    = self.params.interval,
        entity_id   = self.developer.consumer.id,
        start_ts    = self.params.start_ts,
        level       = "cluster",
      }

      local res, err = kong.vitals:get_status_codes(opts)
      return handle_vitals_response(res, err, helpers)
    end,
  },

  ["/vitals/status_codes/by_consumer_and_route"] = {
    before = function(self, db, helpers)
      auth.authenticate_api_session(self, db, helpers)
      if not kong.configuration.vitals then
        return kong.response.exit(404, { message = "Not found" })
      end
    end,

    GET = function(self, db, helpers)
      local key_by = "route_id"
      local opts = {
        entity_type = "consumer_route",
        duration    = self.params.interval,
        entity_id   = self.developer.consumer.id,
        start_ts    = self.params.start_ts,
        level       = "cluster",
      }

      local res, err = kong.vitals:get_status_codes(opts, key_by)
      return handle_vitals_response(res, err, helpers)
    end
  },

  ["/vitals/consumers/cluster"] = {
    before = function(self, db, helpers)
      auth.authenticate_api_session(self, db, helpers)
      if not kong.configuration.vitals then
        return kong.response.exit(404, { message = "Not found" })
      end
    end,

    GET = function(self, db, helpers)
      local opts = {
        consumer_id = self.developer.consumer.id,
        duration    = self.params.interval,
        start_ts    = self.params.start_ts,
        level       = "cluster",
      }

      local res, err = kong.vitals:get_consumer_stats(opts)
      return handle_vitals_response(res, err, helpers)
    end
  },
}
