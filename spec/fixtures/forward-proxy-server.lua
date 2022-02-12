local _M = {}

local function proxy(role, read, write)
  coroutine.yield()

  while not ngx.worker.exiting() do
    local data, err = read:receiveany(1024)

    if data then
      ngx.log(ngx.DEBUG, "got chunk from ", role, ", size: ", #data)
      assert(write:send(data))

    elseif err ~= "timeout" then
      ngx.log(ngx.ERR, "got error reading from ", role, ": ", err)
      break
    end
  end

  return role
end

--- poor man's CONNECT forward proxy
--
-- NGINX will throw a 400 at the HTTP CONNECT method, so this has to be
-- implemented in stream land.
function _M.connect()
  ngx.log(ngx.NOTICE, "incoming forward proxy request")

  local client = assert(ngx.req.socket(true))
  client:settimeouts(500, 500, 500)

  local reader = client:receiveuntil("\r\n\r\n")
  local req = assert(reader())

  local method, target, version
  local headers = {}

  for line in req:gmatch("([^\r\n]+)") do
    if not method then
      method, target, version = line:match("^([A-Z]+)%s+([^%s]+)%s+HTTP/(.+)")

      if not method then
        ngx.log(ngx.WARN, "failed parsing http request: ", req)
        return ngx.exit(444)

      elseif method ~= "CONNECT" then
        ngx.log(ngx.WARN, "received invalid method: ", method)
        return ngx.exit(444)
      end

    else
      local header, value = line:match("([^:]+):%s*(.+)")
      if not header then
        ngx.log(ngx.WARN, "failed parsing header line: ", line)
        return ngx.exit(444)
      end

      headers[header:lower()] = value
    end
  end

  ngx.log(ngx.ERR, "Got request: ", require("inspect")({
    method = method,
    target = target,
    version = version,
    headers = headers,
  }))


  ngx.log(ngx.INFO, "Connecting to ", target)
  local upstream = assert(ngx.socket.tcp())
  upstream:settimeouts(500, 500, 500)

  local host, port = target:match("([^:]+):(.+)")

  local ok, err = upstream:connect(host, port)
  if not ok then
    ngx.log(ngx.ERR, "failed connecting to upstream ", target, ": ", err)
    client:send("HTTP/1.1 502 bad things happened\r\n\r\n")
    return ngx.exit(444)
  end

  ngx.log(ngx.INFO, "Connected!")

  assert(client:send("HTTP/1.1 200 Connection established\r\n\r\n"))

  local ds = ngx.thread.spawn(proxy, "client", client, upstream)
  local us = ngx.thread.spawn(proxy, "upstream", upstream, client)

  local ok, res = ngx.thread.wait(us, ds)
  if not ok then
    ngx.log(ngx.ERR, "thread returned error: ", res)
    ngx.thread.kill(us)
    ngx.thread.kill(ds)

  else
    ngx.log(ngx.NOTICE, res, " thread has completed")

    local wait
    if res == "upstream" then
      wait = ds
    else
      wait = us
    end

    ok, res = ngx.thread.wait(wait)
    if not ok then
      ngx.log(ngx.ERR, "thread returned error: ", res)
    end
  end

  return ngx.exit(0)
end


return _M
