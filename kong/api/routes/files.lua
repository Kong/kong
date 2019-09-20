local endpoints    = require "kong.api.endpoints"
local crud_helpers = require "kong.portal.crud_helpers"
local renderer     = require "kong.portal.renderer"
local utils        = require "kong.tools.utils"
local file_helpers = require "kong.portal.file_helpers"
local workspaces = require "kong.workspaces"
local constants = require "kong.constants"

local kong = kong
local tonumber = tonumber

local unescape_uri = ngx.unescape_uri
local ws_constants = constants.WORKSPACE_CONFIG


local function is_legacy()
  local workspace = workspaces.get_workspace()
  return workspaces.retrieve_ws_config(ws_constants.PORTAL_IS_LEGACY, workspace)
end


local function find_file(db, file_pk)
  local id = unescape_uri(file_pk)
  if utils.is_valid_uuid(id) then
    return db.files:select({ id = file_pk })
  end

  return db.files:select_by_path(file_pk)
end


return {
  ["/files"] = {
    before = function(self, db, helpers)
      crud_helpers.exit_if_portal_disabled()
    end,

    -- List all files stored in the portal file system
    GET = function(self, db, helpers, parent)
      local size = tonumber(self.params.size or 100)
      local offset = self.params.offset
      local type = self.params.type

      self.params.size = nil
      self.params.offset = nil

      if not is_legacy() then
        self.params.type = nil
      end

      local files, _, err_t = db.files:select_all(self.params)
      if not files then
        return endpoints.handle_error(err_t)
      end

      local post_process = function(file)
        if not file then
          return
        end

        if not type or not file.path then
          return file
        end

        local is_content = file_helpers.is_content_path(file.path) or
                           file_helpers.is_spec_path(file.path)

        if type == "content" and is_content then
          return file
        end
      end

      local res, _, err_t = crud_helpers.paginate(
        self, '/files', files, size, offset, post_process
      )

      if not res then
        return endpoints.handle_error(err_t)
      end

      if type and res.next ~= ngx.null then
        res.next = res.next .. "&type=" .. type
      end

      return kong.response.exit(200, res)
    end,
  },

  ["/files/partials/*"] = {
    before = function(self, db, helpers)
      crud_helpers.exit_if_portal_disabled()

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
      local partials_dict = renderer.find_partials_in_page(self.file.contents, {})
      local partials = {}

      for idx, partial in pairs(partials_dict) do
        table.insert(partials, partial)
      end
      return kong.response.exit(200, {
        data = partials
      })
    end
  },

  ["/files/:files"] = {
    before = function(self, db, helpers)
      crud_helpers.exit_if_portal_disabled()
    end,
  },
}
