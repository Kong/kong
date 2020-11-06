-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"
local ee_typedefs = require "kong.enterprise_edition.db.typedefs"

return {
  name         = "consumers",
  primary_key  = { "id" },
  endpoint_key = "username",
  workspaceable = true,
  dao           = "kong.db.dao.consumers",

  fields = {
    { id             = typedefs.uuid, },
    { created_at     = typedefs.auto_timestamp_s },
    { username       = { type = "string",  unique = true }, },
    { custom_id      = { type = "string",  unique = true }, },
    { type           = ee_typedefs.consumer_type { required = true } },
    { tags           = typedefs.tags },
  },

  entity_checks = {
    { at_least_one_of = { "custom_id", "username" } },
  },
}
