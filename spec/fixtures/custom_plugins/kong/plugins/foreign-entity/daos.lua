-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"


return {
  {
    name = "foreign_entities",
    primary_key = { "id" },
    endpoint_key = "name",
    cache_key = { "name" },
    admin_api_name = "foreign-entities",
    fields = {
      { id = typedefs.uuid },
      { name = { type = "string", unique = true } },
      { same = typedefs.uuid },
    },
  },
  {
    name = "foreign_references",
    primary_key = { "id" },
    endpoint_key = "name",
    admin_api_name = "foreign-references",
    fields = {
      { id = typedefs.uuid },
      { name = { type = "string", unique = true } },
      { same = { type = "foreign", reference = "foreign_entities", on_delete = "cascade" } },
    },
  },
}
