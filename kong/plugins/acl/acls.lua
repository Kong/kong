local singletons = require "kong.singletons"


local type = type


local invalidate_cache = function(self, entity)
  local consumer = entity.consumer
  if type(consumer) ~= "table" then
    return true
  end

  -- skip next lines in some tests where singletons is not available
  if not singletons.cache then
    return true
  end

  local cache_key = self:cache_key(consumer.id)

  return singletons.cache:invalidate(cache_key)
end


local _ACLs = {}

function _ACLs:post_crud_event(operation, entity)
  local _, err, err_t = invalidate_cache(self, entity)
  if err then
    return nil, err, err_t
  end

  return self.super.post_crud_event(self, operation, entity)
end


return _ACLs
