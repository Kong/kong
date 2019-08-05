local typedefs = require "kong.db.schema.typedefs"

return {
    gql_ratelimiting_cost_decoration = {
        name = "gql_ratelimiting_cost_decoration",
        primary_key = { "id" },
        endpoint_key = "type_path",

        fields = {
            { id = typedefs.uuid },
            { type_path = {
                required = true, unique = true, type = "string"
            } },
            { add_arguments = {
                default = {}, type = "array", elements = { type = "string" }
            } },
            { add_constant = {
                default = 0, type = "number"
            } },
            { mul_arguments =  {
                default = {}, type = "array", elements = { type = "string" }
            } },
            { mul_constant = {
                default = 1, type = "number"
            } },
            { created_at = typedefs.auto_timestamp_s }
        }
    }
}
