-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

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
