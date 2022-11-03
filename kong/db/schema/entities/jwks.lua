-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"

return {
  name         = "jwks",
  dao          = "kong.db.dao.jwks",
  primary_key  = { "id" },
  cache_key    = { "kid", "set" },
  endpoint_key = "name",
  ttl          = true,
  fields       = {
    {
      id = typedefs.uuid,
    },
    {
      set = {
        type      = "foreign",
        required  = false,
        reference = "jwk_sets",
        on_delete = "cascade",
      },
    },
    {
      name = {
        type     = "string",
        required = false,
        unique   = true,
      },
    },
    {
      -- TODO: Not sure if this is neccessary here. The KID should be part of the jwk object I think.
      --       maybe a shorthandfield that injects jwks.jwk.kid to the toplevel jwks.kid? Is that possible?
      kid = {
        type     = "string",
        required = true,
      },
    },
    {
      jwk = typedefs.jwk
    },
    {
      tags = typedefs.tags,
    },
    {
      created_at = typedefs.auto_timestamp_s,
    },
    {
      updated_at = typedefs.auto_timestamp_s,
    },
  },
}
