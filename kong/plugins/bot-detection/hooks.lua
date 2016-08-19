local events = require "kong.core.events"
local bot_cache = require "kong.plugins.bot-detection.cache"

local function invalidate(message_t)
  if message_t.collection == "plugins" and message_t.entity.name == "bot-detection" then
    bot_cache.reset()
  end
end

return {
  [events.TYPES.ENTITY_UPDATED] = function(message_t)
    invalidate(message_t)
  end
}