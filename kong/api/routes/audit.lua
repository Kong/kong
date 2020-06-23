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
    schema = kong.db.audit_requests.schema,
    methods = {
      GET = endpoints.get_collection_endpoint(kong.db.audit_objects.schema),
    }
  },
}
