local api_helpers = require "kong.api.api_helpers"
local reports     = require "kong.reports"
local utils       = require "kong.tools.utils"


local function post_process(data)
  local r_data = utils.deep_copy(data)
  r_data.config = nil
  r_data.e = "s"
  reports.send("api", r_data)
  return data
end


return {
  ["/services"] = {
    POST = function(self, _, _, parent)
      api_helpers.resolve_url_params(self)
      return parent()
    end,
  },

  ["/services/:services"] = {
    PUT = function(self, _, _, parent)
      api_helpers.resolve_url_params(self)
      return parent()
    end,
    PATCH = function(self, _, _, parent)
      api_helpers.resolve_url_params(self)
      return parent()
    end,
  },

  ["/services/:services/plugins"] = {
    POST = function(_, _, _, parent)
      return parent(post_process)
    end,
  },
}
