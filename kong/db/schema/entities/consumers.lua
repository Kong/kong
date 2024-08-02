-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"
local ee_typedefs = require "kong.enterprise_edition.db.typedefs"

return {
  name          = "consumers",
  primary_key   = { "id" },
  endpoint_key  = "username",
  workspaceable = true,
  dao           = "kong.db.dao.consumers",

  fields        = {
    { id = typedefs.uuid, },
    { created_at = typedefs.auto_timestamp_s },
    { updated_at = typedefs.auto_timestamp_s },
    {
      username = {
        description =
        "The unique username of the Consumer. You must send at least one of username or custom_id with the request.",
        type = "string",
        unique = true,
        indexed = true
      },
    },
    {
      custom_id =
      {
        description = "Stores the existing unique ID of the consumer. You must send at least one of username or custom_id with the request.",
        type = "string",
        unique = true,
        indexed = true
      },
    },
    { type = ee_typedefs.consumer_type { required = true, indexed = true } },
    { tags = typedefs.tags },
    { username_lower = {
      type = "string",
      prefix_ws = true,
      db_export = false,
      description = "The lowercase representation of a username"
    }, },
  },

  entity_checks = {
    { at_least_one_of = { "custom_id", "username" } },
  },
}
