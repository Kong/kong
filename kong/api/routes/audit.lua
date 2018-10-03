local singletons = require "kong.singletons"
local crud = require "kong.api.crud_helpers"

if not singletons.configuration.audit_log then
  return {}
end

return {
  ["/audit/requests"] = {
    GET = function(self, dao_factory)
      crud.paginated_set(self, dao_factory.audit_requests)
    end,
  },

  ["/audit/objects"] = {
    GET = function(self, dao_factory)
      crud.paginated_set(self, dao_factory.audit_objects)
    end,
  },
}
