local events = require "kong.core.events"
local cache = require "kong.tools.database_cache"

local function invalidate(message_t)
  if message_t.collection == "oauth2_credentials" then
    cache.delete(cache.oauth2_credential_key(message_t.old_entity and message_t.old_entity.client_id or message_t.entity.client_id))
    cache.delete(cache.oauth2_credential_key(message_t.entity.id))
  elseif message_t.collection == "oauth2_tokens" then
    cache.delete(cache.oauth2_token_key(message_t.old_entity and message_t.old_entity.access_token or message_t.entity.access_token))
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