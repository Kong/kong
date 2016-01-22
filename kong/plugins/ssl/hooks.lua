local events = require "kong.core.events"
local cache = require "kong.tools.database_cache"

local function invalidate(message_t)
  if message_t.collection == "apis" then
    cache.delete(cache.ssl_data(message_t.entity.id))
  elseif message_t.collection == "plugins" then
    cache.delete(cache.ssl_data(message_t.old_entity and message_t.old_entity.api_id or message_t.entity.api_id))
  end
end

return {
  [events.TYPES.ENTITY_UPDATED] = function(message_t)
    invalidate(message_t)
  end,
  [events.TYPES.ENTITY_DELETED] = function(message_t)
    invalidate(message_t)
  end
}