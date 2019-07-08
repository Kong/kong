local endpoints = require "kong.api.endpoints"

local routes_schema   = kong.db.degraphql_routes.schema
local services_schema = kong.db.services.schema

return {
  ["/services/:services/degraphql/routes"] = {
    schema = routes_schema,
    methods = {
      GET = endpoints.get_collection_endpoint(routes_schema, services_schema, "service"),
      POST = endpoints.post_collection_endpoint(routes_schema, services_schema, "service"),
    },
  },
  ["/services/:services/degraphql/routes/:degraphql_routes"] = {
    schema = routes_schema,
    methods = {
      GET = endpoints.get_entity_endpoint(routes_schema),
      PATCH = endpoints.patch_entity_endpoint(routes_schema),
      DELETE = endpoints.delete_entity_endpoint(routes_schema),
    }
  },
}
