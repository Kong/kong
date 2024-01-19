local endpoints = require "kong.api.endpoints"

local message= "Method not allowed"

return {
  ["/workspaces"] = {
    POST = function(...)
      return kong.response.exit(405, { message = message })
    end,
  },

  ["/workspaces/:workspaces"] = {
    PATCH = function(...)
      return kong.response.exit(405, { message = message })
    end,

    PUT = function(...)
      return kong.response.exit(405, { message = message })
    end,

    DELETE = function(...)
      return kong.response.exit(405, { message = message })
    end,
  },

  -- deactivate endpoints
  ["/workspaces/:workspaces/meta"] = endpoints.disable,
}
