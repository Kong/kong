-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"

return {
  name = "jwe-decrypt",
  fields = {
    { protocols = typedefs.protocols_http },
    { consumer_group = typedefs.no_consumer_group },
    { consumer = typedefs.no_consumer },
    { config = {
      type = "record",
      fields = {
        { lookup_header_name = { description = "The name of the header to look for the JWE token.", type = "string",
          required = true,
          default = "Authorization"
        } },
        { forward_header_name = { description = "The name of the header that is used to set the decrypted value.", type = "string",
          required = true,
          default = "Authorization"
        } },
        { key_sets = { description = "Denote the name or names of all Key Sets that should be inspected when trying to find a suitable key to decrypt the JWE token.", type = "array",
          elements = { type = "string" },
          required = true
        } },
        { strict = { description = "Defines how the plugin behaves in cases where no token was found in the request. When using `strict` mode, the request requires a token to be present and subsequently raise an error if none could be found.", type = "boolean",
            default = true,
          }
        }
      },
    },
    }
  }
}
