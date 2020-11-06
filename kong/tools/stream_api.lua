
local pairs = pairs
local st_format = string.format
local tb_concat = table.concat
local setmetatable = setmetatable


local stream_api = {}

local _endpoints = {}


function stream_api.register(t)
  for path, handler in pairs(t) do
    if type(path) == "string" and type(handler) == "function" then
      _endpoints[path] = handler
    end
  end
end


local stream_mt = {}
stream_mt.__index = stream_mt

function stream_api.serve()
  local req = setmetatable({ socket = ngx.req.socket() }, stream_mt)

  local path = req:get_path()
  local handler = path and _endpoints[path]
  if handler then
    req:exit(handler(req))

  else
    req:exit(req:response("404 Not Found"))
  end
end

--- Returns the initial request line.
function stream_mt:get_line()
  if not self.req_line then
    self.req_line = self.socket:receive("*l")
    self.method, self.path = self.req_line:match("^%s*(%S+)%s+(%S+)")
  end

  return self.req_line
end

--- Returns the "method" part of the request line, actually just the first
--- non-space fragment of the line.
function stream_mt:get_method()
  if not self.method then
    self:get_line()
  end

  return self.method
end

--- Returns the "path" part of the request line, actually it's just the second
--- non-space fragment of the line. This is the only part that determines
--- which handler gets called.
function stream_mt:get_path()
  if not self.path then
    self:get_line()
  end

  return self.path
end

--- Returns a Lua table with the request headers. Keys are all lowercase and
--- replaces '-' with '_'. If two or more headers have the same key, they're
--- concatenated with a space between them. There's no multiline header handling.
function stream_mt:get_headers()
  if not self.headers then
    local headers = {}

    while true do
      local l = self.socket:receive("*l")
      if l == "" then
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

--- Returns the request body. If there was a content_length header, reads this
--- many bytes. Otherwise, reads until the end of the connection.
function stream_mt:get_body()
  if not self.body then
    if not self.content_length then
      self.content_length = tonumber(self:get_headers().content_length)
    end
    self.body = self.socket:receive(self.content_length or "*a")
  end

  return self.body
end

--- Constructs an HTTP/1.0 response as a Lua string. status can be a number
--- (like 200) or string (like "404 Not Found"). headers is a Lua table; the
--- keys are not canonicalized before serializing.
function stream_mt:response(status, headers, body)
  local o = {"HTTP/1.0 " .. tostring(status)}

  if headers then
    for k, v in pairs(headers or {}) do
      o[#o + 1] = st_format("%s: %s", k, v)
    end
  end

  o[#o + 1] = ""
  o[#o + 1] = body or ""

  return tb_concat(o, "\r\n")
end

--- Sends the payload (if any) on the socket, closes it and terminates
--- the response (the function doesn't return).
function stream_mt:exit(payload)
  if payload then
    self.socket:send(payload)
  end

  self.socket:shutdown("send")
  if self.content_length then
    self.socket:receive("*a")
  end

  return ngx.exit(ngx.OK)
end


return stream_api
