
local endpoints = require "kong.api.endpoints"

local services_schema = kong.db.services.schema
local cost_decoration_schema = kong.db.graphql_ratelimiting_advanced_cost_decoration.schema


return {
    ["/services/:services/graphql-rate-limiting-advanced/costs"] = {
        schema = cost_decoration_schema,
        methods = {
            GET = endpoints.get_collection_endpoint(cost_decoration_schema, services_schema, "service"),
            -- TODO: Verify Type Path notation before updating or inserting
            POST = endpoints.post_collection_endpoint(cost_decoration_schema, services_schema, "service"),
            PUT = endpoints.put_entity_endpoint(cost_decoration_schema, services_schema, "service")
        }
    },
    ["/graphql-rate-limiting-advanced/costs"] = {
        schema = cost_decoration_schema,
        methods = {
            GET = endpoints.get_collection_endpoint(cost_decoration_schema),
            -- TODO: Verify Type Path notation before updating or inserting
            POST = endpoints.post_collection_endpoint(cost_decoration_schema),
            PUT = endpoints.put_entity_endpoint(cost_decoration_schema),
        }
    },
    ["/graphql-rate-limiting-advanced/costs/:graphql_ratelimiting_advanced_cost_decoration"] = {
          schema = cost_decoration_schema,
          methods = {
            GET = endpoints.get_entity_endpoint(cost_decoration_schema),
            PATCH = endpoints.patch_entity_endpoint(cost_decoration_schema),
            DELETE = endpoints.delete_entity_endpoint(cost_decoration_schema),
          },
    }
}
