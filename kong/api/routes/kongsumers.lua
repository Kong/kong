local endpoints = require "kong.api.endpoints"
local reports = require "kong.reports"
local utils = require "kong.tools.utils"


local kong = kong
local null = ngx.null


return {
  ["/kongsumers"] = {
    GET = function(self, db, helpers, parent)
      local args = self.args.uri

      -- Search by custom_id: /kongsumers?custom_id=xxx
      if args.custom_id then
        self.params.kongsumers = args.custom_id
        local kongsumer, _, err_t = endpoints.select_entity(self, db, db.kongsumers.schema, "select_by_custom_id")
        if err_t then
          return endpoints.handle_error(err_t)
        end

        return kong.response.exit(200, {
          data = { kongsumer },
          next = null,
        })
      end

      return parent()
    end,
  },

  ["/kongsumers/:kongsumers/plugins"] = {
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
