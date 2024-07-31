-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"

return {
    {
        name = "graphql_ratelimiting_advanced_cost_decoration",
        primary_key = { "id" },
        endpoint_key = "type_path",

        fields = {
            { id = typedefs.uuid },
            { service = { type = "foreign", reference = "services" } },
            { type_path = {
                required = true, type = "string"
            } },
            { add_arguments = {
                default = {}, type = "array", elements = { type = "string" }
            } },
            { add_constant = {
                default = 1, type = "number"
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
