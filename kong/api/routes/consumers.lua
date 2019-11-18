local endpoints = require "kong.api.endpoints"
local cjson = require "cjson"


local kong = kong
local null = ngx.null


return {
  ["/consumers"] = {
    GET = function(self, db, helpers, parent)
      local args = self.args.uri

      -- Search by custom_id: /consumers?custom_id=xxx
      if args.custom_id then
        local opts = endpoints.extract_options(args, db.consumers.schema, "select")
        local consumer, _, err_t = db.consumers:select_by_custom_id(args.custom_id, opts)
        if err_t then
          return endpoints.handle_error(err_t)
        end

        return kong.response.exit(200, {
          data = setmetatable({ consumer }, cjson.array_mt),
          next = null,
        })
      end

      return parent()
    end,
  },
}
