-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"


return {
	name 				= "login_attempts",
  primary_key 		= { "consumer" },
  ttl = true,
  db_export = false,
	fields = {
		{ created_at     = typedefs.auto_timestamp_s },
		{ consumer       = { type = "foreign", reference = "consumers", required = true } },
		{ attempts       = {
      type = "map",
      required = true,
      keys = typedefs.ip,
      values = {
        type = "integer",
      },
    }},
	},
}
