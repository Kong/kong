local typedefs = require "kong.db.schema.typedefs"

return {
	name = "zipkin",
	fields = {
		{ config = {
				type = "record",
				fields = {
					{ run_on = typedefs.run_on { default = "all", one_of = { "all" } } },
					{ http_endpoint = typedefs.url{ required = true } },
					{ sample_ratio = { type = "number",
					                   default = 0.001,
					                   between = { 0, 1 } } },
				},
		}, },
	},
}
