local api_helpers = require "kong.api.api_helpers"
local reports     = require "kong.reports"
local utils       = require "kong.tools.utils"


return {
  ["/routes/:routes/service"] = {
    PATCH = function(self, _, _, parent)
      api_helpers.resolve_url_params(self)
      return parent()
    end,
  },

  ["/routes/:routes/plugins"] = {
    POST = function(_, _, _, parent)
      local post_process = function(data)
        local r_data = utils.deep_copy(data)
        r_data.config = nil
        r_data.e = "r"
        reports.send("api", r_data)
        return data
      end
      return parent(post_process)
    end,
  },
}
