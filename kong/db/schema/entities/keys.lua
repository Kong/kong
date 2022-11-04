-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"

return {
  name                = "keys",
  dao                 = "kong.db.dao.keys",
  primary_key         = { "id" },
  cache_key           = { "kid", "set" },
  endpoint_key        = "name",
  ttl                 = true,
  fields              = {
    {
      id = typedefs.uuid,
    },
    {
      set = {
        type      = "foreign",
        required  = false,
        reference = "key_sets",
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
      kid = {
        type     = "string",
        required = true,
      },
    },
    {
      jwk = typedefs.jwk
    },
    {
      pem = typedefs.pem
    },
    {
      -- conditionally check for presence of jwk || pem based on key_type
      -- TODO: write validator
      key_type = {
        -- indexed = true,
        -- TODO: can be a separate typedef
        type = "string",
        one_of = {
          "jwk",
          -- not implemented
          -- "pem",
          -- not supported. binary format
          -- "der"
        },
        required = true
      }
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
  entity_checks = {
    { conditional = {
      if_field = "key_type", if_match = { eq = "jwk" },
      then_field = "jwk", then_match = { required = true },
    }, },
    -- { conditional = {
    --   if_field = "key_type", if_match = { eq = "pem" },
    --   then_field = "pem", then_match = { required = true },
    -- }, },
  }
}
