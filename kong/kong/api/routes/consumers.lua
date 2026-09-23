local endpoints = require "kong.api.endpoints"
local cjson = require "cjson"


local kong = kong
local null = ngx.null


return {
  ["/consumers"] = {
    GET = function(self, db, helpers, parent)
      local args = self.args.uri
      local custom_id = args.custom_id

      if custom_id and type(custom_id) ~= "string" or custom_id == "" then
        return kong.response.exit(400, {
          message = "custom_id must be an unempty string",
        })
      end

      -- Search by custom_id: /consumers?custom_id=xxx
      if custom_id then
        local opts, _, err_t = endpoints.extract_options(db, args, db.consumers.schema, "select")
        if err_t then
          return endpoints.handle_error(err_t)
        end

        local consumer, _, err_t = db.consumers:select_by_custom_id(custom_id, opts)
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
