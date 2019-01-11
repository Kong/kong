local endpoints = require "kong.api.endpoints"


local kong = kong


return {
  ["/cache/:key"] = {
    GET = function(self)
      -- probe the cache to see if a key has been requested before

      local ttl, err, value = kong.cache:probe(self.params.key)
      if err then
        kong.log.err(err)
        return endpoints.unexpected()
      end

      if ttl then
        return endpoints.ok(value)
      end

      return endpoints.not_found()
    end,

    DELETE = function(self)
      kong.cache:invalidate_local(self.params.key)

      return endpoints.no_content()
    end,
  },

  ["/cache"] = {
    DELETE = function()
      kong.cache:purge()

      return endpoints.no_content()
    end,
  },
}
