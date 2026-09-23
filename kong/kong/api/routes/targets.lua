local endpoints = require "kong.api.endpoints"


return {
  -- deactivate endpoints (use /upstream/{upstream}/targets instead)
  ["/targets"] = endpoints.disable,
  ["/targets/:targets"] = endpoints.disable,
  ["/targets/:targets/upstream"] = endpoints.disable,
}
