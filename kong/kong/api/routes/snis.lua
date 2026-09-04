local endpoints = require "kong.api.endpoints"


return {
  -- deactivate endpoint (use /certificates/sni instead)
  ["/snis/:snis/certificate"] = endpoints.disable,
}
