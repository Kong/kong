local events = require "kong.core.events"
local cache = require "kong.tools.database_cache"

local function invalidate_cache(consumer_id)
  cache.delete(cache.acls_key(consumer_id))
end

local function invalidate(message_t)
  if message_t.collection == "consumers" then
    invalidate_cache(message_t.entity.id)
  elseif message_t.collection == "acls" then
    invalidate_cache(message_t.entity.consumer_id)
  end
end

return {
  [events.TYPES.ENTITY_CREATED] = function(message_t)
     invalidate(message_t)
  end,
  [events.TYPES.ENTITY_UPDATED] = function(message_t)
    invalidate(message_t)
  end,
  [events.TYPES.ENTITY_DELETED] = function(message_t)
    invalidate(message_t)
  end
}