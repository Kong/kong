local typedefs = require "kong.db.schema.typedefs"


return {
	name 				= "login_attempts",
  primary_key 		= { "consumer" },
  ttl = true,
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
