local kong_meta = require "kong.meta"

local resp_phase = {}


resp_phase.PRIORITY = 950
resp_phase.VERSION = kong_meta.version


function resp_phase:access()
end

function resp_phase:response()
end

return resp_phase
