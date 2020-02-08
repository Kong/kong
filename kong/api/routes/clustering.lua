local clustering = require("kong.clustering")
local kong = kong


return {
  ["/clustering/status"] = {
    GET = function(self, db, helpers)
      if kong.configuration.role ~= "control_plane" then
        return kong.response.exit(400, {
          message = "this endpoint is only available when Kong is " ..
                    "configured to run as Control Plane for the cluster"
        })
      end

      return kong.response.exit(200, clustering.get_status())
    end,
  },
}
