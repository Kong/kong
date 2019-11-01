local cjson = require "cjson"
local utils = require "kong.tools.utils"

local kong = kong
local ngx = ngx

return {
  ["/metadata/plugins/:name"] = {
    GET = function(self, db, helpers, parent)
      ngx.log(ngx.DEBUG, "self.params: ", cjson.encode(self.params))
      local name = self.params.name
      if not name then
        return kong.response.exit(400, { message = "Bad query" })
      end

      -- TODO: either unload module or use loadfile() instead
      local ok, meta = utils.load_module_if_exists("kong.plugins." .. name .. ".metadata")
      if not ok or not meta then
        return kong.response.exit(404, { message = "Not found" })
      end

      return kong.response.exit(200, meta)
    end,
  },
}
