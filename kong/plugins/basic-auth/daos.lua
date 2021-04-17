-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"
local crypto = require "kong.plugins.basic-auth.crypto"


return {
  basicauth_credentials = {
    name = "basicauth_credentials",
    primary_key = { "id" },
    cache_key = { "username" },
    endpoint_key = "username",
    workspaceable = true,
    admin_api_name = "basic-auths",
    admin_api_nested_name = "basic-auth",
    fields = {
      { id = typedefs.uuid },
      { created_at = typedefs.auto_timestamp_s },
      { consumer = { type = "foreign", reference = "consumers", required = true, on_delete = "cascade" }, },
      { username = { type = "string", required = true, unique = true }, },
      { password = { type = "string", required = true , encrypted = true }, },
      { tags     = typedefs.tags },
    },
    transformations = {
      {
        input = { "password" },
        needs = { "consumer.id" },
        on_write = function(password, consumer_id)
          return { password = crypto.hash(consumer_id, password) }
        end,
      },
    },
  },
}
