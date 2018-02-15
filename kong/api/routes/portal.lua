local crud        = require "kong.api.crud_helpers"
local singletons  = require "kong.singletons"


-- Disable API when Developer Portal is not enabled
if not singletons.configuration.portal then
  return {}
end


return {
  ["/files"] = {
    -- List all files stored in the portal file system
    GET = function(self, dao_factory, helpers)
      crud.paginated_set(self, dao_factory.portal_files)
    end,

    -- Create or Update a file in the portal file system
    POST = function(self, dao_factory, helpers)
      crud.post(self.params, dao_factory.portal_files)
    end
  },

  ["/files/*"] = {
    -- Process request prior to handling the method
    before = function(self, dao_factory, helpers)
      local dao = dao_factory.portal_files
      local identifier = self.params.splat

      -- Find a file by id or field "name"
      local rows, err = crud.find_by_id_or_field(dao, {}, identifier, "name")
      if err then
        return helpers.yield_error(err)
      end

      -- Since we know both the name and id of portal_files are unique
      self.params.splat = nil
      self.portal_file = rows[1]
      if not self.portal_file then
        return helpers.responses.send_HTTP_NOT_FOUND(
          "No file found by name or id '" .. identifier .. "'"
        )
      end
    end,

    -- Retrieve an individual file from the portal file system
    GET = function(self, dao_factory, helpers)
      return helpers.responses.send_HTTP_OK(self.portal_file)
    end,

    PATCH = function(self, dao_factory)
      crud.patch(self.params, dao_factory.portal_files, self.portal_file)
    end,

    -- Delete a file in the portal file system that has
    -- been created outside of migrations
    DELETE = function(self, dao_factory, helpers)
      crud.delete(self.portal_file, dao_factory.portal_files)
    end
  }
}

