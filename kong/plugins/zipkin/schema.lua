local typedefs = require "kong.db.schema.typedefs"

return {
	name = "zipkin",
	fields = {
		{ run_on = typedefs.run_on { default = "all" } },
		{ config = {
				type = "record",
				fields = {
					{ http_endpoint = typedefs.url{ required = true } },
					{ sample_ratio = { type = "number",
					                   default = 0.001,
					                   between = { 0, 1 } } },
                                        { default_service_name = { type = "string", default = nil } },
					{ include_credential = { type = "boolean", required = true, default = true } },
				},
		}, },
	},
}
