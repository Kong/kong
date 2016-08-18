local match = string.match
local utils = require "kong.tools.utils"

local hostname_type = utils.hostname_type

-- Resolves the target structure in-place.
-- If the hostname matches an 'upstream' pool, then it must be balanced in that 
-- pool, in this case any port number provided will be ignored, as the pool provides it.
-- @param hostname the hostname to resolve, may include a port number
-- @param tries
-- @return true on success, nil+error otherwise
local function execute(target)
  local upstream_host = target.upstream_host
  if not target.type then
    local typ = hostname_type(upstream_host)
for port determination we need the protool; http or https to insert the default ports for those
so probably replace passing the url as a string by a table, and only reconstruct at the
last moment, 
Best location would be the resolver. maybe store both the table as well as the constructed string.

    if typ == "ipv4" then
      local name, port = match(upstream_host, "^([^:]+)%:*(%d*)$")
      
    elseif typ = "ipv6" then
    else
    end
    


    
  end
  if target.tries ~= 1 then
    -- retry; we need to fetch an alternative upstream target here.....but how?
    --
    -- WARNING: this runs in the BALANCER_BY_LUA, which does not allow yielding (hence no cosockets)!
    -- so no live DNS lookups nor database updates!
    return
  end
  
  
end

return { 
  execute = execute,
}