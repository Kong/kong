-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

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
