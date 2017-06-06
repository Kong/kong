local events = require "kong.core.events"
local cache  = require "kong.tools.database_cache"

local function invalidate(t)
      if t.collection == "oic_issuers" then
    cache.delete("oic:" .. t.old_entity and t.old_entity.issuer or t.entity.issuer)
  elseif t.collection == "oic_revoked" then
    cache.delete("oic:" .. t.old_entity and t.old_entity.hash or t.entity.hash)
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
