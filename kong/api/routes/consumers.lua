local endpoints = require "kong.api.endpoints"
local reports = require "kong.reports"
local utils = require "kong.tools.utils"


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
          data = { consumer },
          next = null,
        })
      end

      return parent()
    end,
  },

  ["/consumers/:consumers/plugins"] = {
    POST = function(_, _, _, parent)
      local post_process = function(data)
        local r_data = utils.deep_copy(data)
        r_data.config = nil
        r_data.e = "c"
        reports.send("api", r_data)
        return data
      end
      return parent(post_process)
    end,
  },
}
