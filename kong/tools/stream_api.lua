
local stream_api = {}

local _endpoints = {}


function stream_api.register_endpoint(path, handler)
  _endpoints[path] = handler
end


function stream_api.serve()
  local sock = assert(ngx.req.socket())
  local line = sock:receive()

  local path = line:match("^%S+%s+(%S+)")
  local handler = path and _endpoints[path]
  if handler then
    handler(sock, line)
  else
    stream_api.send_response(sock, "404 Not Found")
  end
end


function stream_api.get_headers(socket)
  local o = {}

  while true do
    local l = socket:receive("*l")
    if l == "" then
      return o
    end

    local k, v = l:match("^%s*(%S+)%s*:%s*(.*)$")
    if k then
      k = k:lower():gsub('-', '_')
      if o[k] then
        v = o[k] .. " " .. v
      end

      o[k] = v
    end
  end
end


function stream_api:serialize_headers(headers)
  local o = {}
  for k, v in pairs(headers) do
    o[#o + 1] = string.format("%s: %s", k, v)
  end
  return table.concat(o, "\r\n")
end


function stream_api.send_response(socket, status, headers, body)
  socket:send("HTTP/1.1 " .. tostring(status) .. "\r\n")

  if headers then
    if type(headers) ~= "string" then
      headers = stream_api.serialize_headers(headers)
    end

    socket:send(headers)
  end
  socket:send("\r\n")

  if body then
    socket:send(body)
  end

  socket:shutdown("send")
end


return stream_api
