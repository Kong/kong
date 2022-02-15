local _M = {}

local split = require("kong.tools.utils").split


-- This is a very naive forward proxy, which accepts a CONNECT over HTTP, and
-- then starts tunnelling the bytes blind (for end-to-end SSL).
function _M.connect()

  local req_sock = ngx.req.socket(true)
  req_sock:settimeouts(1000, 1000, 1000)

  -- receive request line
  local req_line = req_sock:receive()
  ngx.log(ngx.DEBUG, "request line: ", req_line)

  local method, host_port, version = unpack(split(req_line, " "))
  if method ~= "CONNECT" then
    return ngx.exit(400)
  end

  local upstream_host, upstream_port = unpack(split(host_port, ":"))

  -- receive and discard any headers
  repeat
    local line = req_sock:receive("*l")
    ngx.log(ngx.DEBUG, "request header: ", line)
  until ngx.re.find(line, "^\\s*$", "jo")

  -- Connect to requested upstream
  local upstream_sock = ngx.socket.tcp()
  upstream_sock:settimeouts(1000, 1000, 1000)
  local ok, err = upstream_sock:connect(upstream_host, upstream_port)
  if not ok then
    return ngx.exit(504)
  end

  -- Tell the client we are good to go
  ngx.print("HTTP/1.1 200 OK\n\n")
  ngx.flush()

  -- 10Kb in either direction should be plenty
  local max_bytes = 10 * 1024

  repeat
    local req_data = req_sock:receiveany(max_bytes)
    if req_data then
      ngx.log(ngx.DEBUG, "client RCV ", #req_data, " bytes")

      local bytes, err = upstream_sock:send(req_data)
      if bytes then
        ngx.log(ngx.DEBUG, "upstream SND ", bytes, " bytes")
      end
    end

    local res_data = upstream_sock:receiveany(max_bytes)
    if res_data then
      ngx.log(ngx.DEBUG, "upstream RCV ", #res_data, " bytes")

      local bytes, err = req_sock:send(res_data)
      if bytes then
        ngx.log(ngx.DEBUG, "client SND: ", bytes, " bytes")
      end
    end
  until not req_data and not res_data -- request socket should be closed

  upstream_sock:close()
end

return _M
