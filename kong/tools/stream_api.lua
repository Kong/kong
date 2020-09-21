
local stream_api = {}

local _endpoints = {}


function stream_api.register_endpoint(path, handler)
  _endpoints[path] = handler
end


local stream_mt = {}
stream_mt.__index = stream_mt

function stream_api.serve()
  local req = setmetatable({ socket = ngx.req.socket() }, stream_mt)

  local path = req:get_path()
  local handler = path and _endpoints[path]
  if handler then
    req:exit(handler(req))
  end

  req:exit(req:response("404 Not Found"))
end


function stream_mt:get_line()
  if not self.req_line then
    self.req_line = self.socket:receive("*l")
  end

  return self.req_line
end

function stream_mt:get_path()
  if not self.path then
    self.path = self:get_line():match("^%S+%s+(%S+)")
  end

  return self.path
end

function stream_mt:get_headers()
  if not self.headers then
    local headers = {}

    while true do
      local l = self.socket:receive("*l")
      if l == "" then
        self.headers = headers
        break
      end

      local k, v = l:match("^%s*(%S+)%s*:%s*(.*)%s*$")
      if k then
        k = k:lower():gsub('-', '_')
        if headers[k] then
          v = headers[k] .. " " .. v
        end
        headers[k] = v
      end
    end

    self.headers = headers
  end

  return self.headers
end

function stream_mt:get_body()
  if not self.body then
    if not self.content_length then
      self.content_length = tonumber(self:get_headers().content_length)
    end
    self.body = self.socket:receive(self.content_length or "*a")
  end

  return self.body
end

function stream_mt:response(status, headers, body)
  local o = {"HTTP/1.1 " .. tostring(status)}

  if headers then
    if type(body) == "string" then
      headers["Content-Length"] = #body
    end

    for k, v in pairs(headers or {}) do
      o[#o + 1] = string.format("%s: %s", k, v)
    end
  end

  o[#o + 1] = ""
  o[#o + 1] = body or ""

  return table.concat(o, "\r\n")
end

function stream_mt:exit(payload)
  if payload then
    self.socket:send(payload)
  end

  self.socket:shutdown("send")
end


return stream_api
