local stream_api = require "kong.tools.stream_api"

local echo_mod = {
  PRIORITY = 1000,
}

stream_api.register_endpoint("/echo", function(sock, reqline)
  local headers = stream_api.get_headers(sock)
  local body = sock:receive(tonumber(headers.content_length))
  --print ("body: ", tostring(line))

  stream_api.send_response(sock, 200, nil, body)
end)


return echo_mod

