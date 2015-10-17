local responses = require "kong.tools.responses"
local cache = require "kong.tools.database_cache"

return {
  ["/cache/"] = {
    DELETE = function(self, dao_factory)
      cache.delete_all()
      return responses.send_HTTP_NO_CONTENT()
    end
  },

  ["/cache/:key"] = {
    GET = function(self, dao_factory)
      if self.params.key then
        local cached_item = cache.get(self.params.key)
        if cached_item then
          return responses.send_HTTP_OK(cached_item)
        end
      end
      
      return responses.send_HTTP_NOT_FOUND()
    end,

    DELETE = function(self, dao_factory)
      if self.params.key then
        cache.delete(self.params.key)
        return responses.send_HTTP_NO_CONTENT()
      end
      
      return responses.send_HTTP_NOT_FOUND()
    end
  }
}
