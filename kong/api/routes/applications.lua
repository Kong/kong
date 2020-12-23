-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local crud_helpers = require "kong.portal.crud_helpers"
local endpoints    = require "kong.api.endpoints"


local auth_plugins = {
  ["oauth2"] = { name = "oauth2", dao = "oauth2_credentials" },
}


return {
  ["/applications"] = {
    before = function(self, db, helpers)
      crud_helpers.exit_if_portal_disabled()
    end,
  },

  ["/applications/:applications"] = {
    before = function(self, db, helpers)
      crud_helpers.exit_if_portal_disabled()
    end
  },

  ["/applications/:applications/application_instances"] = {
    before = function(self, db, helpers)
      crud_helpers.exit_if_portal_disabled()

      local application_pk = self.params.applications
      self.params.applications = nil

      local application, _, err_t = db.applications:select({ id = application_pk })
      if err_t then
        return endpoints.handle_error(err_t)
      end

      if not application then
        return kong.response.exit(404, { message = "Not found" })
      end

      self.application = application
    end,

    POST = function(self, db, helpers)
      return crud_helpers.create_application_instance(self, db, helpers)
    end,

    GET = function(self, db, helpers)
      return crud_helpers.get_application_instances_by_application(self, db, helpers)
    end,
  },

  ["/applications/:applications/application_instances/:application_instances"] = {
    before = function(self, db, helpers)
      crud_helpers.exit_if_portal_disabled()

      local application_pk = self.params.applications
      self.params.applications = nil

      local application, _, err_t = db.applications:select({ id = application_pk })
      if err_t then
        return endpoints.handle_error(err_t)
      end

      if not application then
        return kong.response.exit(404, { message = "Not found" })
      end

      self.application = application

      local application_instance_pk = self.params.application_instances
      self.params.application_instances = nil

      local application_instance, _, err_t = db.application_instances:select({ id = application_instance_pk })
      if err_t then
        return endpoints.handle_error(err_t)
      end

      self.application_instance = application_instance
    end,

    GET = function(self, db, helpers)
      if not self.application_instance or self.application_instance.application.id ~= self.application.id then
        return kong.response.exit(404, { message = "Not found" })
      end

      return crud_helpers.get_application_instance(self, db, helpers)
    end,

    PATCH = function(self, db, helpers)
      if not self.application_instance or self.application_instance.application.id ~= self.application.id then
        return kong.response.exit(404, { message = "Not found" })
      end

      return crud_helpers.update_application_instance(self, db, helpers)
    end,

    DELETE = function(self, db, helpers)
      if not self.application_instance or self.application_instance.application.id ~= self.application.id then
        return kong.response.exit(204)
      end

      return crud_helpers.delete_application_instance(self, db, helpers)
    end,
  },

  ["/applications/:applications/credentials/:plugin"] = {
    before = function(self, db, helpers)
      crud_helpers.exit_if_portal_disabled()
      crud_helpers.exit_if_external_oauth2()

      local application_pk = self.params.applications
      self.params.applications = nil

      local application, _, err_t = db.applications:select({ id = application_pk })
      if err_t then
        return endpoints.handle_error({ id = application_pk })
      end

      if not application then
        return kong.response.exit(404, { message = "Not found" })
      end

      self.application = application

      local plugin_name = self.params.plugin
      local plugin = auth_plugins[plugin_name]
      if not plugin then
        return kong.response.exit(404, { message = "Not found" })
      end

      self.plugin = plugin
    end,

    GET = function(self, db, helpers, parent)
      self.credential_collection = db.daos[self.plugin.dao]
      self.consumer = { id = self.application.consumer.id }

      return crud_helpers.get_credentials(self, db, helpers)
    end,

    POST = function(self, db, helpers)
      return crud_helpers.create_app_reg_credentials(self, db, helpers)
    end
  },

  ["/applications/:applications/credentials/:plugin/:credential_id"] = {
    before = function(self, db, helpers)
      crud_helpers.exit_if_portal_disabled()
      crud_helpers.exit_if_external_oauth2()

      local application_pk = self.params.applications
      self.params.applications = nil

      local application, _, err_t = db.applications:select({ id = application_pk })
      if err_t then
        return endpoints.handle_error(err_t)
      end

      if not application then
        return kong.response.exit(404, { message = "Not found" })
      end

      self.consumer = application.consumer

      local plugin_name = self.params.plugin
      local plugin = auth_plugins[plugin_name]
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
}
