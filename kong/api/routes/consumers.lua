local Endpoints = require "kong.api.endpoints"
local reports = require "kong.reports"
local utils = require "kong.tools.utils"


return {

  ["/consumers"] = {
    GET = function(self, db, helpers, parent)

      -- Search by custom_id: /consumers?custom_id=xxx
      if self.params.custom_id then
        local consumer, _, err_t =
          db.consumers:select_by_custom_id(self.params.custom_id)
        if err_t then
          return Endpoints.handle_error(err_t)
        end

        return helpers.responses.send_HTTP_OK {
          data = { consumer },
        }
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
