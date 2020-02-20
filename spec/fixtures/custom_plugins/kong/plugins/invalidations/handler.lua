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
