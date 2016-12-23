local responses = require "kong.tools.responses"
local cache = require "kong.tools.database_cache"

-- Create a table of functions per cache type
local caches
do
  local cache_names = {}
  caches = setmetatable({
    lua = function(action, ...)
      if action == "get" then
        return cache.get(...)
      elseif action == "delete" then
        return cache.delete(...)
      elseif action == "delete_all" then
        return cache.delete_all(...)
      end
    end,
    shm = function(action, ...)
      if action == "get" then
        return cache.sh_get(...)
      elseif action == "delete" then
        return cache.sh_delete(...)
      elseif action == "delete_all" then
        return cache.sh_delete_all(...)
      end
    end,
  }, {
    __index = function(self, key)
      return responses.send_HTTP_BAD_REQUEST("invalid cache type; '"..
             tostring(key).."', valid caches are: "..cache_names)
    end,
  })

  -- build string with valid cache names (for error mesage above)
  for name in pairs(caches) do cache_names[#cache_names+1] = "'"..name.."'" end
  table.sort(cache_names)  -- make order deterministic, for test purposes
  cache_names = table.concat(cache_names, ", ")
end

return {
  ["/cache/"] = {
    before = function(self)
      self.params.cache = self.params.cache or "lua"
    end,

    DELETE = function(self, dao_factory)
      caches[self.params.cache]("delete_all")
      return responses.send_HTTP_NO_CONTENT()
    end
  },

  ["/cache/:key"] = {
    before = function(self)
      self.params.cache = self.params.cache or "lua"
    end,

    GET = function(self, dao_factory)
      if self.params.key then
        local cached_item = caches[self.params.cache]("get", self.params.key)
        if cached_item ~= nil then
          return responses.send_HTTP_OK(cached_item)
        end
      end

      return responses.send_HTTP_NOT_FOUND()
    end,

    DELETE = function(self, dao_factory)
      if self.params.key then
        caches[self.params.cache]("delete", self.params.key)
        return responses.send_HTTP_NO_CONTENT()
      end

      return responses.send_HTTP_NOT_FOUND()
    end
  }
}