local utils         = require "kong.tools.rand"

local function get(conf, resource, version)
  -- Return a random string every time
  kong.log.err("get() called")
  return utils.random_string()
end


return {
  VERSION = "1.0.0",
  get = get,
}
