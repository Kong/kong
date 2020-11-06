-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"


return {
  {
    name = "unique_foreigns",
    primary_key = { "id" },
    admin_api_name = "unique-foreigns",
    fields = {
      { id = typedefs.uuid },
      { name = { type = "string" }, },
    },
  },
  {
    name = "unique_references",
    primary_key = { "id" },
    admin_api_name = "unique-references",
    fields = {
      { id = typedefs.uuid },
      { note = { type = "string" }, },
      { unique_foreign = { type = "foreign", reference = "unique_foreigns", on_delete = "cascade", unique = true }, },
    },
  },
}
