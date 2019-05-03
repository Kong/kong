local endpoints    = require "kong.api.endpoints"
local crud_helpers = require "kong.portal.crud_helpers"
local renderer     = require "kong.portal.renderer"
local utils        = require "kong.tools.utils"

local unescape_uri = ngx.unescape_uri

local function find_file(db, file_pk)
  local id = unescape_uri(file_pk)
  if utils.is_valid_uuid(id) then
    return db.files:select({ id = file_pk })
  end

  return db.files:select_by_name(file_pk)
end


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

      return kong.response.exit(200, paginated_results)
    end,
  },

  ["/files/partials/*"] = {
    before = function(self, db, helpers)
      local file_pk = self.params.splat

      -- Find a file by id or field "name"
      local file, _, err_t = find_file(db, file_pk)
      if not file then
        return endpoints.handle_error(err_t)
      end

      -- Since we know both the name and id of files are unique
      self.file = file
    end,

    GET = function(self, db, helpers)
      local partials_dict = renderer.find_partials_in_page(self.file.contents, {}, true)
      local partials = {}

      for idx, partial in pairs(partials_dict) do
        table.insert(partials, partial)
      end

      return kong.response.exit(200, {data = partials})
    end
  }
}
