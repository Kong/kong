local kong = kong


return {
  ["/cache/:key"] = {
    GET = function(self)
      -- probe the cache to see if a key has been requested before

      local ttl, err, value = kong.cache:probe(self.params.key)
      if err then
        kong.log.err(err)
        return kong.response.exit(500, { message = "An unexpected error happened" })
      end

      if ttl then
        return kong.response.exit(200, type(value) == "table" and value or { message = value })
      end

      ttl, err, value = kong.core_cache:probe(self.params.key)
      if err then
        kong.log.err(err)
        return kong.response.exit(500, { message = "An unexpected error happened" })
      end

      if ttl then
        return kong.response.exit(200, type(value) == "table" and value or { message = value })
      end

      return kong.response.exit(404, { message = "Not found" })
    end,

    DELETE = function(self)
      kong.cache:invalidate_local(self.params.key)

      return kong.response.exit(204) -- no content
    end,
  },

  ["/cache"] = {
    DELETE = function()
      kong.cache:purge()
      kong.core_cache:purge()

      return kong.response.exit(204) -- no content
    end,
  },
}
