local endpoints = require "kong.api.endpoints"


return {
  -- deactivate endpoints (use /upstream/{upstream}/targets instead)
  ["/targets"] = endpoints.not_found,
  ["/targets/:targets"] = endpoints.not_found,
  ["/targets/:targets/upstream"] = endpoints.not_found,
}
