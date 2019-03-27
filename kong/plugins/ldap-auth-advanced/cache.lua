local singletons = require "kong.singletons"
local null = ngx.null


local _M = {}


function _M.consumer_field_cache_key(key, value)
  return singletons.db.consumers:cache_key(key, value, "consumers")
end


function _M.init_worker()
  if not singletons.worker_events or not singletons.worker_events.register then
    return
  end

  singletons.worker_events.register(
    function(data)
      local cache_key = _M.consumer_field_cache_key

      local old_entity = data.old_entity
      if old_entity then
        if old_entity.custom_id and old_entity.custom_id ~= null and old_entity.custom_id ~= "" then
          singletons.cache:invalidate(cache_key("custom_id", old_entity.custom_id))
        end

        if old_entity.username and old_entity.username ~= null and old_entity.username ~= "" then
          singletons.cache:invalidate(cache_key("username", old_entity.username))
        end
      end

      local entity = data.entity
      if entity then
        if entity.custom_id and entity.custom_id ~= null and entity.custom_id ~= "" then
          singletons.cache:invalidate(cache_key("custom_id", entity.custom_id))
        end

        if entity.username and entity.username ~= null and entity.username ~= "" then
          singletons.cache:invalidate(cache_key("username", entity.username))
        end
      end
    end, "crud", "consumers")
end


return _M
