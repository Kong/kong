local stream_api = require "kong.tools.stream_api"

local echo_mod = {
  PRIORITY = 1000,
}

stream_api.register_endpoint("/echo", function(req)
  local body = req:get_body()

  return req:response(200, nil, body)
end)

return echo_mod

