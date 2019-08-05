
local endpoints = require "kong.api.endpoints"

local cost_decoration_schema = kong.db.gql_ratelimiting_cost_decoration.schema


return {
    ["/gql-rate-limiting/costs"] = {
        schema = cost_decoration_schema,
        methods = {
            GET = endpoints.get_collection_endpoint(cost_decoration_schema),
            -- TODO: Verify Type Path notation before updating or inserting
            POST = endpoints.post_collection_endpoint(cost_decoration_schema),
            PUT = endpoints.put_entity_endpoint(cost_decoration_schema)
        }
    }
}
