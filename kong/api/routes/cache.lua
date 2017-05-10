local singletons = require "kong.singletons"

return {
  ["/cache/:key"] = {
    GET = function(self, _, helpers)
      -- probe the cache to see if a key has been requested before

      local ttl, err, value = singletons.cache:probe(self.params.key)
      if err then
        return helpers.responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
      end

      if ttl then
        return helpers.responses.send_HTTP_OK(value)
      end

      return helpers.responses.send_HTTP_NOT_FOUND()
    end,

    DELETE = function(self, _, helpers)
      singletons.cache:invalidate_local(self.params.key)

      return helpers.responses.send_HTTP_NO_CONTENT()
    end,
  },

  ["/cache"] = {
    DELETE = function(self, _, helpers)
      singletons.cache:purge()

      return helpers.responses.send_HTTP_NO_CONTENT()
    end,
  },
}
