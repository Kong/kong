-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

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
      { case = { type = "string", required = false, referenceable = true }, },
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
      {
        on_write = function(entity)
          local case = entity.case
          if not case or case == ngx.null then
            return {}
          end
          return {
            case = string.upper(case),
          }
        end,
        on_read = function(entity)
          local case = entity.case
          if not case or case == ngx.null then
            return {}
          end
          return {
            case = string.lower(case),
          }
        end,
      },
    },
  },
}
