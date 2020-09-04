local endpoints = require "kong.api.endpoints"


return {
  ["/cluster_status"] = {
    GET = function(self, _, _, parent)
      if kong.configuration.role ~= "control_plane" then
        return kong.response.exit(400, {
          message = "this endpoint is only available when Kong is " ..
                    "configured to run as Control Plane for the cluster"
        })
      end

      return parent()
    end,

    POST = endpoints.disable,
    DELETE = endpoints.disable,
  }
}
