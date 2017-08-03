local events = require "kong.core.events"
local cache  = require "kong.tools.database_cache"

local function invalidate(t)
  if t.collection == "oic_issuers" then
    local key = t.old_entity and t.old_entity.issuer or t.entity.issuer
    if key then
      cache.delete("oic_issuers:" .. key)
    end
  end
end

return {
  [events.TYPES.ENTITY_UPDATED] = function(t)
    invalidate(t)
  end,
  [events.TYPES.ENTITY_DELETED] = function(t)
    invalidate(t)
  end
}
