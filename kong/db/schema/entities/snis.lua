-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"

return {
  name         = "snis",
  primary_key  = { "id" },
  endpoint_key = "name",
  dao          = "kong.db.dao.snis",

  workspaceable = true,

  fields = {
    { id           = typedefs.uuid, },
    { name         = typedefs.wildcard_host { required = true, unique = true, unique_across_ws = true }},
    { created_at   = typedefs.auto_timestamp_s },
    { tags         = typedefs.tags },
    { certificate  = { type = "foreign", reference = "certificates", required = true }, },
  },

}
