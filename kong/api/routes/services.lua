local api_helpers = require "kong.api.api_helpers"


return {
  ["/services"] = {
    POST = function(self, _, _, parent)
      api_helpers.resolve_url_params(self)
      return parent()
    end,
  },

  ["/services/:services"] = {
    PATCH  = function(self, _, _, parent)
      api_helpers.resolve_url_params(self)
      return parent()
    end,
  },
}
