local events = require "kong.core.events"
local handler = require "kong.plugins.oauth2-introspection.handler"
local cache = require "kong.tools.database_cache"

local function invalidate(message_t)
  if message_t.collection == "consumers" then
  	local consumer_id_key = handler.consumers_id_key(message_t.old_entity and message_t.old_entity.id or message_t.entity.id)
  	local username = cache.get(consumer_id_key)

  	cache.delete(handler.consumers_username_key(username))
  	cache.delete(consumer_id_key)
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