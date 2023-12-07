-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local endpoints = require "kong.api.endpoints"


local kong = kong


if not kong.configuration.audit_log then
  return {}
end


return {
  ["/audit/requests"] = {
    schema = kong.db.audit_requests.schema,
    methods = {
      GET = endpoints.get_collection_endpoint(kong.db.audit_requests.schema),
    }
  },

  ["/audit/objects"] = {
    schema = kong.db.audit_objects.schema,
    methods = {
      GET = endpoints.get_collection_endpoint(kong.db.audit_objects.schema),
    }
  },
}
