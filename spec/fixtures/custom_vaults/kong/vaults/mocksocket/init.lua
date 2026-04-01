local env = require "kong.vaults.env"


local getenv = os.getenv


local function init()
  env.init()
  assert(getenv("KONG_PROCESS_SECRETS") == nil, "KONG_PROCESS_SECRETS environment variable found")
  assert(env.get({}, "KONG_PROCESS_SECRETS") == nil, "KONG_PROCESS_SECRETS environment variable found")
end


local function get(conf, resource, version)
  return env.get(conf, resource, version)
end


return {
  VERSION = "1.0.0",
  init = init,
  get = get,
}
