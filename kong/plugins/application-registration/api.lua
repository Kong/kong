local cjson        = require "cjson"
local utils        = require "kong.tools.utils"
local crud_helpers = require "kong.portal.crud_helpers"

return {
  ["/services/:services/applications"] = {
    before = function(self, db, helpers)
      local id = self.params.services
      self.params.services = nil

      local service, _, err_t
      if not utils.is_valid_uuid(id) then
        service, _, err_t = kong.db.services:select_by_name(id)
      else
        service, _, err_t = kong.db.services:select({ id = id })
      end

      if not service or err_t then
        return kong.response.exit(404, { message = "Not found" })
      end

      self.service = service
    end,

    GET = function(self, db, helpers)
      local applications = {}
      for row, err in kong.db.application_instances:each_for_service({ id = self.service.id }) do
        local application = kong.db.applications:select({ id = row.application.id })
        if application then
          table.insert(applications, application)
        end
      end

      setmetatable(applications, cjson.empty_array_mt)

      kong.response.exit(200, {
        data = applications,
        total = #applications,
      })
    end,
  },

  ["/services/:services/application_instances"] = {
    before = function(self, db, helpers)
      local id = self.params.services
      self.params.services = nil

      local service, _, err_t
      if not utils.is_valid_uuid(id) then
        service, _, err_t = kong.db.services:select_by_name(id)
      else
        service, _, err_t = kong.db.services:select({ id = id })
      end

      if not service or err_t then
        return kong.response.exit(404, { message = "Not found" })
      end

      self.service = service
    end,

    GET = function(self, db, helpers)
      return crud_helpers.get_application_instances_by_service(self, kong.db, helpers)
    end
  },

  ["/services/:services/application_instances/:application_instances"] = {
    before = function(self, db, helpers)
      local id = self.params.services
      self.params.services = nil

      local service, _, err_t
      if not utils.is_valid_uuid(id) then
        service, _, err_t = kong.db.services:select_by_name(id)
      else
        service, _, err_t = kong.db.services:select({ id = id })
      end

      if not service or err_t then
        return kong.response.exit(404, { message = "Not found" })
      end

      self.service = service

      local application_instance = kong.db.application_instances:select({ id = self.params.application_instances })
      if not application_instance then
        return kong.response.exit(404, { message = "Not found" })
      end

      self.params.application_instances = nil
      self.application_instance = application_instance
    end,

    GET = function(self, db, helpers)
      if self.application_instance.service.id ~= self.service.id then
        return kong.response.exit(404, { message = "Not found" })
      end

      return crud_helpers.get_application_instance(self, kong.db, helpers)
    end,

    PATCH = function(self, db, helpers)
      if self.application_instance.service.id ~= self.service.id then
        return kong.response.exit(404, { message = "Not found" })
      end

      return crud_helpers.update_application_instance(self, kong.db, helpers)
    end,

    DELETE = function(self, db, helpers)
      if self.application_instance.service.id ~= self.service.id then
        return kong.response.exit(204)
      end

      return crud_helpers.delete_application_instance(self, kong.db, helpers)
    end,
  },
}
