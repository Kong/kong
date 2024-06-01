local _M = {}

local split = require("kong.tools.string").split

local header_mt = {
  __index = function(self, name)
    name = name:lower():gsub("_", "-")
    return rawget(self, name)
  end,

  __newindex = function(self, name, value)
    name = name:lower():gsub("_", "-")
    rawset(self, name, value)
  end,
}

local function new_headers()
  return setmetatable({}, header_mt)
end

-- This is a very naive forward proxy, which accepts a CONNECT over HTTP, and
-- then starts tunnelling the bytes blind (for end-to-end SSL).
function _M.connect(opts)
  local req_sock = ngx.req.socket(true)
  req_sock:settimeouts(1000, 1000, 1000)

  -- receive request line
  local req_line = req_sock:receive()
  ngx.log(ngx.DEBUG, "request line: ", req_line)

  local method, host_port = unpack(split(req_line, " "))
  if method ~= "CONNECT" then
    return ngx.exit(400)
  end

  local upstream_host, upstream_port = unpack(split(host_port, ":"))

  local headers = new_headers()

  -- receive headers
  repeat
    local line = req_sock:receive("*l")
    local name, value = line:match("^([^:]+):%s*(.+)$")
    if name and value then
      ngx.log(ngx.DEBUG, "header: ", name, " => ", value)
      headers[name] = value
    end
  until ngx.re.find(line, "^\\s*$", "jo")


  local basic_auth = opts and opts.basic_auth
  if basic_auth then
    ngx.log(ngx.DEBUG, "checking proxy-authorization...")

    local found = headers["proxy-authorization"]
    if not found then
      ngx.log(ngx.NOTICE, "client did not send proxy-authorization header")
      ngx.print("HTTP/1.1 401 Unauthorized\r\n\r\n")
      return ngx.exit(ngx.OK)
    end

    local auth = ngx.re.gsub(found, [[^Basic\s*]], "", "oji")

    if auth ~= basic_auth then
      ngx.log(ngx.NOTICE, "client sent incorrect proxy-authorization")
      ngx.print("HTTP/1.1 403 Forbidden\r\n\r\n")
      return ngx.exit(ngx.OK)
    end

    ngx.log(ngx.DEBUG, "accepted basic proxy-authorization")
  end


  -- Connect to requested upstream
  local upstream_sock = ngx.socket.tcp()
  upstream_sock:settimeouts(1000, 1000, 1000)
  local ok, err = upstream_sock:connect(upstream_host, upstream_port)
  if not ok then
    ngx.log(ngx.ERR, "connect to upstream ", upstream_host, ":", upstream_port,
            " failed: ", err)
    return ngx.exit(504)
  end

  -- Tell the client we are good to go
  ngx.print("HTTP/1.1 200 OK\r\n\r\n")
  ngx.flush()

  ngx.log(ngx.DEBUG, "tunneling started")

  -- 10Kb in either direction should be plenty
  local max_bytes = 10 * 1024

  repeat
    local req_data = req_sock:receiveany(max_bytes)
    if req_data then
      ngx.log(ngx.DEBUG, "client RCV ", #req_data, " bytes")

      local bytes, err = upstream_sock:send(req_data)
      if bytes then
        ngx.log(ngx.DEBUG, "upstream SND ", bytes, " bytes")
      elseif err then
        ngx.log(ngx.ERR, "upstream SND failed: ", err)
      end
    end

    local res_data = upstream_sock:receiveany(max_bytes)
    if res_data then
      ngx.log(ngx.DEBUG, "upstream RCV ", #res_data, " bytes")

      local bytes, err = req_sock:send(res_data)
      if bytes then
        ngx.log(ngx.DEBUG, "client SND: ", bytes, " bytes")
      elseif err then
        ngx.log(ngx.ERR, "client SND failed: ", err)
      end
    end
  until not req_data and not res_data -- request socket should be closed

  upstream_sock:close()

  ngx.log(ngx.DEBUG, "tunneling ended")
end

return _M
