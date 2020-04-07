local typedefs = require "kong.db.schema.typedefs"

-- is required false by default?
-- consumer, protocol, etc. settings
-- enabled on route AND service
return {
	name = "upstream-timeout",
	fields = {
		{ protocols = typedefs.protocols_http },
		{ config = {
				type = "record",
				fields = {
					{ read_timeout = { type = "integer" } },
					{ send_timeout = { type = "integer" } },
					{ connect_timeout = { type = "integer" } }
				}
			}
		}
	}
}
