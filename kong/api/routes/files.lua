local endpoints    = require "kong.api.endpoints"
local crud_helpers = require "kong.portal.crud_helpers"

return {
  ["/files"] = {
    -- List all files stored in the portal file system
    GET = function(self, db, helpers, parent)
      local size = self.params.size or 100
      local offset = self.params.offset

      self.params.size = nil
      self.params.offset = nil

      local files, _, err_t = db.files:select_all(self.params)
      if not files then
        return endpoints.handle_error(err_t)
      end

      local paginated_results, _, err_t = crud_helpers.paginate(
        self, '/files', files, size, offset
      )

      if not paginated_results then
        return endpoints.handle_error(err_t)
      end

      return helpers.responses.send_HTTP_OK(paginated_results)
    end,
  },
}
