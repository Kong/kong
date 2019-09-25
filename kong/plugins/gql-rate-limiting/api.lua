
local endpoints = require "kong.api.endpoints"

local services_schema = kong.db.services.schema
local cost_decoration_schema = kong.db.gql_ratelimiting_cost_decoration.schema


return {
    ["/services/:services/gql-rate-limiting/costs"] = {
        schema = cost_decoration_schema,
        methods = {
            GET = endpoints.get_collection_endpoint(cost_decoration_schema, services_schema, "service"),
            -- TODO: Verify Type Path notation before updating or inserting
            POST = endpoints.post_collection_endpoint(cost_decoration_schema, services_schema, "service"),
            PUT = endpoints.put_entity_endpoint(cost_decoration_schema, services_schema, "service")
        }
    },
    ["/gql-rate-limiting/costs"] = {
        schema = cost_decoration_schema,
        methods = {
            GET = endpoints.get_collection_endpoint(cost_decoration_schema),
            -- TODO: Verify Type Path notation before updating or inserting
            POST = endpoints.post_collection_endpoint(cost_decoration_schema),
            PUT = endpoints.put_entity_endpoint(cost_decoration_schema),
        }
    },
    ["/gql-rate-limiting/costs/:gql_ratelimiting_cost_decoration"] = {
          schema = cost_decoration_schema,
          methods = {
            GET = endpoints.get_entity_endpoint(cost_decoration_schema),
            PATCH = endpoints.patch_entity_endpoint(cost_decoration_schema),
            DELETE = endpoints.delete_entity_endpoint(cost_decoration_schema),
          },
    }
}
