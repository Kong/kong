-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local kong = kong
local assert = assert


local counts = {}


local Invalidations = {
  PRIORITY = 0
}


function Invalidations:init_worker()
  assert(kong.cluster_events:subscribe("invalidations", function(key)
    counts[key] = (counts[key] or 0) + 1
  end))
end


function Invalidations:access(_)
  return kong.response.exit(200, counts)
end


return Invalidations
