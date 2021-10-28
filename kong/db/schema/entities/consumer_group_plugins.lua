-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"
local ee_typedefs = require "kong.enterprise_edition.db.typedefs"

return {
  name         = "consumer_group_plugins",
  generate_admin_api  = false,
  admin_api_nested_name = "plugins",
  primary_key  = { "id" },
  endpoint_key = "name",
  workspaceable = true,

  fields = {
    { id             = typedefs.uuid },
    { created_at     = typedefs.auto_timestamp_s },
    { consumer_group           = { type = "foreign", required = true, reference = "consumer_groups", on_delete = "cascade" }, },
    { name           = { type = "string", required = true, unique = true }, },
    { config         = { type = "record", fields = {
      { window_size = {
        type = "array",
        elements = {
          type = "number",
        },
        required = true,
      }},
      { window_type = {
        type = "string",
        one_of = { "fixed", "sliding" },
        default = "sliding",
      }},
      { limit = {
        type = "array",
        elements = {
          type = "number",
        },
        required = true,
      }},
      { sync_rate = {
        type = "number",
      }},
      { retry_after_jitter_max = { -- in seconds
      type = "number",
      default = 0,
    }},
    }, required = true
    },
  }},
}
