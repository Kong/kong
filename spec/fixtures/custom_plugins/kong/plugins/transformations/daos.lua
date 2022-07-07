local typedefs = require "kong.db.schema.typedefs"


return {
  {
    name = "transformations",
    primary_key = { "id" },
    endpoint_key = "name",
    fields = {
      { id = typedefs.uuid },
      { name = { type = "string" }, },
      { secret = { type = "string", required = false, auto = true }, },
      { hash_secret = { type = "boolean", required = true, default = false }, },
      { meta = { type = "string", required = false, referenceable = true }, },
    },
    transformations = {
      {
        input = { "hash_secret" },
        needs = { "secret" },
        on_write = function(hash_secret, client_secret)
          if not hash_secret then
            return {}
          end
          local hash = assert(ngx.md5(client_secret))
          return {
            secret = hash,
          }
        end,
      },
      {
        input = { "meta" },
        on_write = function(meta)
          if not meta or meta == ngx.null then
            return {}
          end
          return {
            meta = string.reverse(meta),
          }
        end,
        on_read = function(meta)
          if not meta or meta == ngx.null then
            return {}
          end
          return {
            meta = string.reverse(meta),
          }
        end,
      },
    },
  },
}
