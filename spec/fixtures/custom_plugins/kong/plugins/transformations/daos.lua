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
    },
  },
}
