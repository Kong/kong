local env = require "kong.vaults.env"
local http = require "resty.http"


local getenv = os.getenv


local get_phase = ngx.get_phase


local function init()
  env.init()
  assert(getenv("KONG_PROCESS_SECRETS") == nil, "KONG_PROCESS_SECRETS environment variable found")
  assert(env.get({}, "KONG_PROCESS_SECRETS") == nil, "KONG_PROCESS_SECRETS environment variable found")
end


local function get(conf, resource, version)
  -- simulate a real vault backend that makes HTTP requests (yield via cosocket)
  -- pcall is needed because cosocket may not be available in all phases (e.g. init)
  local phase = get_phase()
  if phase ~= "init" and phase ~= "init_worker" then
    assert(pcall(function()
      local test = require "kong.vaults.test"
      local httpc = http.new()
      httpc:set_timeout(50)
      httpc:request_uri("http://127.0.0.1:" .. test.PORT .. "/secret/dummy", {
        keepalive = false,
      })
    end))
  end

  return env.get(conf, resource, version)
end


return {
  VERSION = "1.0.0",
  init = init,
  get = get,
}
