-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local constants    = require "kong.constants"
local workspaces   = require "kong.workspaces"
local utils        = require "kong.tools.utils"
local endpoints    = require "kong.api.endpoints"
local portal_smtp_client = require "kong.portal.emails"
local crud_helpers = require "kong.portal.crud_helpers"
local enums   = require "kong.enterprise_edition.dao.enums"
local secrets = require "kong.enterprise_edition.consumer_reset_secret_helpers"
local dao_helpers = require "kong.portal.dao_helpers"
local workspace_config = require "kong.portal.workspace_config"


local cjson = require "cjson"
local rbac = require "kong.rbac"

local kong = kong
local tonumber = tonumber

local PORTAL_PREFIX = constants.PORTAL_PREFIX
-- Adds % in front of "special characters" such as -
local ESCAPED_PORTAL_PREFIX = PORTAL_PREFIX:gsub("([^%w])", "%%%1")

local unescape_uri = ngx.unescape_uri
local ws_constants = constants.WORKSPACE_CONFIG

local auth_plugins = {
  ["basic-auth"] = { name = "basic-auth", dao = "basicauth_credentials", credential_key = "password" },
  ["oauth2"] =     { name = "oauth2",     dao = "oauth2_credentials" },
  ["hmac-auth"] =  { name = "hmac-auth",  dao = "hmacauth_credentials" },
  ["jwt"] =        { name = "jwt",        dao = "jwt_secrets" },
  ["key-auth"] =   { name = "key-auth",   dao = "keyauth_credentials", credential_key = "key" },
  ["openid-connect"] = { name = "openid-connect" },
}


local app_auth_plugins = {
  ["oauth2"] = { name = "oauth2", dao = "oauth2_credentials" },
}


local function remove_portal_prefix(str)
  return string.gsub(str, "^" .. ESCAPED_PORTAL_PREFIX, "")
end


local function validate_credential_plugin(self, db, helpers)
  local plugin_name = ngx.unescape_uri(self.params.plugin)

  self.credential_plugin = auth_plugins[plugin_name]
  if not self.credential_plugin then
    return kong.response.exit(404, { message = "Not found" })
  end

  self.credential_collection = db.daos[self.credential_plugin.dao]
end


local function find_developer(db, developer_pk)
  local id = unescape_uri(developer_pk)
  if utils.is_valid_uuid(id) then
    return db.developers:select({ id = developer_pk })
  end

  return db.developers:select_by_email(developer_pk)
end

local function set_developer(self, db)
  self.developer = find_developer(db, self.params.developers)
  if not self.developer then
    return kong.response.exit(404, { message = "Not found" })
  end
  self.params.developers = nil
end

local function set_application(self, db)
  local application_pk = self.params.applications

  local application, _, err_t = db.applications:select({ id = application_pk })
  if err_t then
    return endpoints.handle_error(err_t)
  end

  if not application then
    return kong.response.exit(404, { message = "Not found" })
  end

  if self.developer and application.developer.id ~= self.developer.id then
    return kong.response.exit(404, { message = "Not found" })
  end

  self.application = application
  self.consumer = application.consumer
  self.params.applications = nil
end

local function set_plugin(self, db)
  local plugin, err, err_t = db.plugins:select({ id = self.params.id })
  if err then
    return endpoints.handle_error(err_t)
  end
  self.consumer = self.devloper and self.developer.consumer
  if not plugin or plugin.consumer and self.consumer
      and plugin.consumer.id ~= self.consumer.id then
    return kong.response.exit(404, { message = "Not found" })
  end

  self.params.id = nil
  self.plugin = plugin
end

local function get_developer_status()
  local workspace = workspaces.get_workspace()
  local auto_approve = workspace_config.retrieve(ws_constants.PORTAL_AUTO_APPROVE,
                                                     workspace)

  if auto_approve then
    return enums.CONSUMERS.STATUS.APPROVED
  end

  return enums.CONSUMERS.STATUS.PENDING
end


local function preprocess_role(row)
  row.is_default = nil
  row.name = remove_portal_prefix(row.name)
  return row
end


local function preprocess_role_with_permissions(row)
  row = preprocess_role(row)
  row.permissions = rbac.readable_endpoints_permissions({ row })
  return row
end


local function filter_and_preprocess_roles(row)
  if not row.is_default and string.sub(row.name, 1, #PORTAL_PREFIX) == PORTAL_PREFIX then
    return preprocess_role(row)
  end
end


local roles_schema = kong.db.rbac_roles.schema
local get_role_endpoint    = endpoints.get_entity_endpoint(roles_schema)
local delete_role_endpoint = endpoints.delete_entity_endpoint(roles_schema)
local patch_role_endpoint  = endpoints.patch_entity_endpoint(roles_schema)
local post_roles_endpoint  = endpoints.post_collection_endpoint(roles_schema)


return {
  ["/developers"] = {
    before = function(self, db, helpers)
      crud_helpers.exit_if_portal_disabled()
    end,

    GET = function(self, db, helpers, parent)
      local filter_by_role = self.params.role

      self.params.offset = nil
      self.params.size = nil
      self.params.role = nil
      self.params.status = tonumber(self.params.status)

      local developers = {}
      for developer, err in db.developers:each() do
        if err then
          return endpoints.handle_error(err)
        end

        local ok = true
        if self.params.status and self.params.status ~= developer.status then
          ok = false
        end
        if self.params.custom_id and self.params.custom_id ~= developer.custom_id then
          ok = false
        end
        if ok then
          table.insert(developers, developer)
        end
      end

      local post_process = function(developer)
        if not developer then
          return
        end

        local roles, err = kong.db.developers:get_roles(developer)
        if err then
          return endpoints.handle_error(err)
        end

        developer.roles = roles

        if not filter_by_role then
          return developer
        end

        -- filtering by role
        if roles and #roles then
          for i, current_role in ipairs(roles) do
            if current_role == filter_by_role then
              return developer
            end
          end
        end
      end

      local res, _, err_t = crud_helpers.paginate(self, developers,
                                                  post_process)
      if not res then
        return endpoints.handle_error(err_t)
      end

      return kong.response.exit(200, res)
    end,

    POST = function(self, db, helpers)
      if not self.params.status then
        self.params.status = get_developer_status()
      end

      local developer, _, err_t = db.developers:insert(self.params)
      if not developer then
        return endpoints.handle_error(err_t)
      end

      local name_or_email = dao_helpers.get_name_or_email(developer)

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
        local token_ttl =
          workspace_config.retrieve(ws_constants.PORTAL_TOKEN_EXP,
                                        workspace)

        local jwt, err = secrets.create(developer.consumer, ngx.var.remote_addr,
                                        token_ttl)

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

      return kong.response.exit(200, developer)
    end,
  },

  ["/developers/roles"] = {
    before = function(self, db, helpers)
      crud_helpers.exit_if_portal_disabled()
    end,

    GET = function(self, db, helpers, parent)
      local roles = {}
      for role, err in db.rbac_roles:each() do
        if err then
          return endpoints.handle_error(err)
        end
        table.insert(roles, role)
      end

      local res, _, err_t = crud_helpers.paginate(self, roles,
                                                  filter_and_preprocess_roles)
      if not res then
        return endpoints.handle_error(err_t)
      end

      return kong.response.exit(200, res)
    end,

    POST = function(self, db, helpers, parent)
      if type(self.args.post.name) == "string" then
        if self.args.post.name == "*" then
          return kong.response.exit(400, { message = "Invalid role '*'" })
        end

        self.args.post.name = PORTAL_PREFIX .. self.args.post.name
      end

      local next_page = "/developers/roles"
      return post_roles_endpoint(self, db, helpers, preprocess_role_with_permissions, next_page)
    end,
  },

  ["/developers/export"] = {
    before = function (self, db, helpers)
      crud_helpers.exit_if_portal_disabled()
    end,

    GET = function(self, db, helpers)
      local csvString = 'Email, Status\n'
      for developer, err in db.developers:each() do
        if err then
          return endpoints.handle_error(err)
        end

        local status_label = enums.CONSUMERS.STATUS_LABELS[developer.status]
        csvString = csvString .. developer.email .. ',' ..  status_label .. '\n'
      end
      return kong.response.exit(200, csvString, {
        ["Content-Type"] = "text/csv",
        ["Content-Disposition"] = "attachment; filename=\"developers.csv\"",
      })
    end,
  },

  ["/developers/roles/:rbac_roles"] = {
    before = function(self, db, helpers)
      crud_helpers.exit_if_portal_disabled()

      if type(self.params.rbac_roles) == "string" and
         not utils.is_valid_uuid(self.params.rbac_roles) then
        self.params.rbac_roles = PORTAL_PREFIX .. self.params.rbac_roles
      end
    end,

    GET = function(self, db, helpers)
      return get_role_endpoint(self, db, helpers, preprocess_role_with_permissions)
    end,
    PATCH = function(self, db, helpers)
      if type(self.args.post.name) == "string" then
        if self.args.post.name == "*" then
          return kong.response.exit(400, { message = "Invalid role '*'" })
        end

        self.args.post.name = PORTAL_PREFIX .. self.args.post.name
      end

      return patch_role_endpoint(self, db, helpers, preprocess_role_with_permissions)
    end,
    DELETE = delete_role_endpoint,
  },

  ["/developers/:developers"] = {
    before = function(self, db, helpers)
      crud_helpers.exit_if_portal_disabled()
      set_developer(self, db)
    end,

    GET = function(self, db, helpers)
      local developer = self.developer
      developer.roles = kong.db.developers:get_roles(developer)

      return kong.response.exit(200, developer)
    end,

    PATCH = function(self, db, helpers)
      -- save previous status
      local developer = self.developer
      local previous_status = developer.status

      local developer, _, err_t = db.developers:update(developer, self.params)
      if not developer then
        return endpoints.handle_error(err_t)
      end

      developer.roles = kong.db.developers:get_roles(developer)

      local res = { developer = developer }
      if developer.status == enums.CONSUMERS.STATUS.APPROVED and
         developer.status ~= previous_status and
         previous_status ~= enums.CONSUMERS.STATUS.REVOKED then

        local name_or_email = dao_helpers.get_name_or_email(developer)

        local portal_emails = portal_smtp_client.new()
        local email_res, err = portal_emails:approved(developer.email, name_or_email)
        if err then
          if err.code then
            return kong.response.exit(err.code, { message = err.message })
          end

          return endpoints.handle_error(err)
        end

        res.email = email_res
      end

      return kong.response.exit(200, res)
    end,
    DELETE = function(self, db, helpers)
      local _, _, err_t = db.developers:delete(self.developer, self.params)
      if err_t then
        return endpoints.handle_error(err_t)
      end

      return kong.response.exit(204)
    end
  },

  ["/developers/:developers/applications"] = {
    before = function(self, db, helpers)
      crud_helpers.exit_if_portal_disabled()
      set_developer(self, db)
    end,

    POST = function(self, db, helpers)
      local application = {
        developer = self.developer,
        name = self.params.name,
        redirect_uri = self.params.redirect_uri,
        custom_id = self.params.custom_id
      }

      local application, _, err_t = kong.db.applications:insert(application)
      if err_t then
        return endpoints.handle_error(err_t)
      end

      return kong.response.exit(201, application)
    end,

    GET = function(self, db, helpers)
      local applications = {}
      for application, err in kong.db.applications:each_for_developer(self.developer) do
        table.insert(applications, application)
      end

      setmetatable(applications, cjson.empty_array_mt)

      local res, _, err_t = crud_helpers.paginate(self, applications)
      if not res then
        return endpoints.handle_error(err_t)
      end

      return kong.response.exit(200, res)
    end,
  },

  ["/developers/:developers/applications/:applications"] = {
    before = function(self, db, helpers)
      crud_helpers.exit_if_portal_disabled()
      set_developer(self, db)
      set_application(self, db)
    end,

    GET = function(self, db, helpers)
      return kong.response.exit(200, self.application)
    end,

    PATCH = function(self, db, helpers)
      local params = {
        name = self.params.name,
        redirect_uri = self.params.redirect_uri,
        custom_id = self.params.custom_id
      }

      local application, _, err_t =
          kong.db.applications:update({ id = self.application.id }, params)

      if not application then
        return endpoints.handle_error(err_t)
      end

      return kong.response.exit(200, application)
    end,

    DELETE = function(self, db, helpers)
      local _, _, err_t = kong.db.applications:delete({ id = self.application.id })
      if err_t then
        return endpoints.handle_error(err_t)
      end

      return kong.response.exit(204)
    end
  },

  ["/developers/:developers/applications/:applications/credentials/:plugin"] = {
    before = function(self, db, helpers)
      crud_helpers.exit_if_portal_disabled()
      crud_helpers.exit_if_external_oauth2()

      set_developer(self, db)
      set_application(self, db)

      local plugin_name = self.params.plugin
      local plugin = app_auth_plugins[plugin_name]
      if not plugin then
        return kong.response.exit(404, { message = "Not found" })
      end

      self.plugin = plugin
    end,

    GET = function(self, db, helpers)
      self.credential_collection = db.daos[self.plugin.dao]
      self.consumer = { id = self.application.consumer.id }

      return crud_helpers.get_credentials(self, db, helpers)
    end,

    POST = function(self, db, helpers)
      return crud_helpers.create_app_reg_credentials(self, db, helpers)
    end,
  },


  ["/developers/:developers/applications/:applications/credentials/:plugin/:credential_id"] = {
    before = function(self, db, helpers)
      crud_helpers.exit_if_portal_disabled()
      crud_helpers.exit_if_external_oauth2()

      set_developer(self, db)
      set_application(self, db)

      local plugin_name = self.params.plugin
      local plugin = app_auth_plugins[plugin_name]
      if not plugin then
        return kong.response.exit(404, { message = "Not found" })
      end

      self.credential_collection = db.daos[plugin.dao]
    end,

    GET = function(self, db, helpers)
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

  ["/developers/:developers/applications/:applications/application_instances"] = {
    before = function(self, db, helpers)
      crud_helpers.exit_if_portal_disabled()

      set_developer(self, db)
      set_application(self, db)
    end,

    POST = function(self, db, helpers)
      return crud_helpers.create_application_instance(self, db, helpers)
    end,

    GET = function(self, db, helpers)
      return crud_helpers.get_application_instances_by_application(self, db, helpers)
    end,
  },

  ["/developers/:developers/applications/:applications/application_instances/:application_instances"] = {
    before = function(self, db, helpers)
      crud_helpers.exit_if_portal_disabled()

      set_developer(self, db)
      set_application(self, db)

      local application_instance_pk = self.params.application_instances
      self.params.application_instances = nil

      local application_instance, _, err_t =
        db.application_instances:select({ id = application_instance_pk })

      if err_t then
        return endpoints.handle_error(err_t)
      end

      self.application_instance = application_instance
    end,

    GET = function(self, db, helpers)
      if not self.application_instance
         or self.application_instance.application.id ~= self.application.id then
        return kong.response.exit(404, { message = "Not found" })
      end

      return kong.response.exit(200, self.application_instance)
    end,

    PATCH = function(self, db, helpers)
      if not self.application_instance
         or self.application_instance.application.id ~= self.application.id then
        return kong.response.exit(404, { message = "Not found" })
      end

      return crud_helpers.update_application_instance(self, db, helpers)
    end,

    DELETE = function(self, db, helpers)
      if not self.application_instance
         or self.application_instance.application.id ~= self.application.id then
        return kong.response.exit(204)
      end

      return crud_helpers.delete_application_instance(self, db, helpers)
    end,
  },

  ["/developers/:developers/plugins/"] = {
    before = function(self, db, helpers)
      crud_helpers.exit_if_portal_disabled()
      set_developer(self, db)
    end,

    GET = function(self, db, helpers)
      local consumer = self.developer.consumer
      local plugins = setmetatable({}, cjson.empty_array_mt)

      for row, err in db.plugins:each_for_consumer(consumer) do
        if err then
          return endpoints.handle_error(err)
        end

        table.insert(plugins, row)
      end

      return kong.response.exit(200, plugins)
    end,

    POST = function(self, db, helpers)
      self.params.consumer = self.developer.consumer

      local ok, _, err_t = db.plugins:insert(self.params)
      if not ok then
        return endpoints.handle_error(err_t)
      end

      return kong.response.exit(201, ok)
    end,
  },

  ["/developers/:developers/plugins/:id"] = {
    before = function(self, db, helpers)
      crud_helpers.exit_if_portal_disabled()
      set_developer(self, db)
      set_plugin(self, db)
    end,

    GET = function(self, db, helpers)
      return kong.response.exit(200, self.plugin)
    end,

    PATCH = function(self, db, helpers)
      local ok, _, err_t = db.plugins:update(self.plugin, self.params)
      if not ok then
        return endpoints.handle_error(err_t)
      end

      return kong.response.exit(200, ok)
    end,

    DELETE = function(self, db, helpers)
      local ok, _, err_t = db.plugins:delete(self.plugin)
      if not ok then
        return endpoints.handle_error(err_t)
      end

      return kong.response.exit(204)
    end
  },

  ["/developers/:developers/credentials/:plugin"] = {
    before = function(self, db, helpers)
      crud_helpers.exit_if_portal_disabled()
      validate_credential_plugin(self, db, helpers)
      set_developer(self, db)
    end,

    GET = function(self, db, helpers)
      self.consumer = self.developer.consumer
      return crud_helpers.get_credentials(self, db, helpers)
    end,

    POST = function(self, db, helpers)
      self.params.consumer = self.developer.consumer
      return crud_helpers.create_credential(self, db, helpers)
    end,
  },

  ["/developers/:developers/credentials/:plugin/:credential_id"] = {
    before = function(self, db, helpers)
      crud_helpers.exit_if_portal_disabled()
      validate_credential_plugin(self, db, helpers)
      set_developer(self, db)
      self.consumer = self.developer and self.developer.consumer
    end,

    GET = function(self, db, helpers)
      return crud_helpers.get_credential(self, db, helpers)
    end,

    PATCH = function(self, db, helpers)
      return crud_helpers.update_credential(self, db, helpers)
    end,

    DELETE = function(self, db, helpers)
      return crud_helpers.delete_credential(self, db, helpers)
    end,
  },

  ["/developers/invite"] = {
    before = function(self, db, helpers)
      crud_helpers.exit_if_portal_disabled()
    end,

    POST = function(self, db, helpers)
      if not self.params.emails or next(self.params.emails) == nil then
        return kong.response.exit(400, { message = "emails param required" })
      end
      local portal_emails = portal_smtp_client.new()
      local res, err = portal_emails:invite(self.params.emails)
      if err then
        if err.code then
          return kong.response.exit(err.code, { message = err.message })
        end

        return endpoints.handle_error(err)
      end

      return kong.response.exit(200, res)
    end
  },
}
