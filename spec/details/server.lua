-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

------------------------------------------------------------------
-- Collection of utilities to help testing Kong features and plugins.
--
-- @copyright Copyright 2016-2022 Kong Inc. All rights reserved.
-- @license [Apache 2.0](https://opensource.org/licenses/Apache-2.0)
-- @module spec.helpers


local CONSTANTS = require("spec.details.constants")


---
-- TCP/UDP server helpers
--
-- @section servers


--- Starts a local TCP server.
-- Accepts a single connection (or multiple, if given `opts.requests`)
-- and then closes, echoing what was received (last read, in case
-- of multiple requests).
-- @function tcp_server
-- @tparam number port The port where the server will be listening on
-- @tparam[opt] table opts options defining the server's behavior with the following fields:
-- @tparam[opt=60] number opts.timeout time (in seconds) after which the server exits
-- @tparam[opt=1] number opts.requests the number of requests to accept before exiting
-- @tparam[opt=false] bool opts.tls make it a TLS server if truthy
-- @tparam[opt] string opts.prefix a prefix to add to the echoed data received
-- @return A thread object (from the `llthreads2` Lua package)
-- @see kill_tcp_server
local function tcp_server(port, opts)
  local threads = require "llthreads2.ex"
  opts = opts or {}
  if CONSTANTS.TEST_COVERAGE_MODE == "true" then
    opts.timeout = CONSTANTS.TEST_COVERAGE_TIMEOUT
  end
  local thread = threads.new({
    function(port, opts)
      local socket = require "socket"
      local server = assert(socket.tcp())
      server:settimeout(opts.timeout or 60)
      assert(server:setoption("reuseaddr", true))
      assert(server:bind("*", port))
      assert(server:listen())
      local line
      local oks, fails = 0, 0
      local handshake_done = false
      local n = opts.requests or 1
      for _ = 1, n + 1 do
        local client, err
        if opts.timeout then
          client, err = server:accept()
          if err == "timeout" then
            line = "timeout"
            break

          else
            assert(client, err)
          end

        else
          client = assert(server:accept())
        end

        if opts.tls and handshake_done then
          local ssl = require "spec.details.ssl"

          local params = {
            mode = "server",
            protocol = "any",
            key = "spec/fixtures/kong_spec.key",
            certificate = "spec/fixtures/kong_spec.crt",
          }

          client = ssl.wrap(client, params)
          client:dohandshake()
        end

        line, err = client:receive()
        if err == "closed" then
          fails = fails + 1

        else
          if not handshake_done then
            assert(line == "\\START")
            client:send("\\OK\n")
            handshake_done = true

          else
            if line == "@DIE@" then
              client:send(string.format("%d:%d\n", oks, fails))
              client:close()
              break
            end

            oks = oks + 1

            client:send((opts.prefix or "") .. line .. "\n")
          end

          client:close()
        end
      end
      server:close()
      return line
    end
  }, port, opts)

  local thr = thread:start()

  -- not necessary for correctness because we do the handshake,
  -- but avoids harmless "connection error" messages in the wait loop
  -- in case the client is ready before the server below.
  ngx.sleep(0.001)

  local sock = ngx.socket.tcp()
  sock:settimeout(0.01)
  while true do
    if sock:connect("localhost", port) then
      sock:send("\\START\n")
      local ok = sock:receive()
      sock:close()
      if ok == "\\OK" then
        break
      end
    end
  end
  sock:close()

  return thr
end


--- Stops a local TCP server.
-- A server previously created with `tcp_server` can be stopped prematurely by
-- calling this function.
-- @function kill_tcp_server
-- @param port the port the TCP server is listening on.
-- @return oks, fails; the number of successes and failures processed by the server
-- @see tcp_server
local function kill_tcp_server(port)
  local sock = ngx.socket.tcp()
  assert(sock:connect("localhost", port))
  assert(sock:send("@DIE@\n"))
  local str = assert(sock:receive())
  assert(sock:close())
  local oks, fails = str:match("(%d+):(%d+)")
  return tonumber(oks), tonumber(fails)
end


local code_status = {
  [200] = "OK",
  [201] = "Created",
  [202] = "Accepted",
  [203] = "Non-Authoritative Information",
  [204] = "No Content",
  [205] = "Reset Content",
  [206] = "Partial Content",
  [207] = "Multi-Status",
  [300] = "Multiple Choices",
  [301] = "Moved Permanently",
  [302] = "Found",
  [303] = "See Other",
  [304] = "Not Modified",
  [305] = "Use Proxy",
  [307] = "Temporary Redirect",
  [308] = "Permanent Redirect",
  [400] = "Bad Request",
  [401] = "Unauthorized",
  [402] = "Payment Required",
  [403] = "Forbidden",
  [404] = "Not Found",
  [405] = "Method Not Allowed",
  [406] = "Not Acceptable",
  [407] = "Proxy Authentication Required",
  [408] = "Request Timeout",
  [409] = "Conflict",
  [410] = "Gone",
  [411] = "Length Required",
  [412] = "Precondition Failed",
  [413] = "Payload Too Large",
  [414] = "URI Too Long",
  [415] = "Unsupported Media Type",
  [416] = "Range Not Satisfiable",
  [417] = "Expectation Failed",
  [418] = "I'm a teapot",
  [422] = "Unprocessable Entity",
  [423] = "Locked",
  [424] = "Failed Dependency",
  [426] = "Upgrade Required",
  [428] = "Precondition Required",
  [429] = "Too Many Requests",
  [431] = "Request Header Fields Too Large",
  [451] = "Unavailable For Legal Reasons",
  [500] = "Internal Server Error",
  [501] = "Not Implemented",
  [502] = "Bad Gateway",
  [503] = "Service Unavailable",
  [504] = "Gateway Timeout",
  [505] = "HTTP Version Not Supported",
  [506] = "Variant Also Negotiates",
  [507] = "Insufficient Storage",
  [508] = "Loop Detected",
  [510] = "Not Extended",
  [511] = "Network Authentication Required",
}


local EMPTY = {}


local function handle_response(code, body, headers)
  if not code then
    code = 500
    body = ""
    headers = EMPTY
  end

  local head_str = ""

  for k, v in pairs(headers or EMPTY) do
    head_str = head_str .. k .. ": " .. v .. "\r\n"
  end

  return code .. " " .. code_status[code] .. " HTTP/1.1" .. "\r\n" ..
          "Content-Length: " .. #body .. "\r\n" ..
          "Connection: close\r\n" ..
          head_str ..
          "\r\n" ..
          body
end


local function handle_request(client, response)
  local lines = {}
  local headers = {}
  local line, err

  local content_length
  repeat
    line, err = client:receive("*l")
    if err then
      return nil, err
    else
      local k, v = line:match("^([^:]+):%s*(.+)$")
      if k then
        headers[k] = v
        if k:lower() == "content-length" then
          content_length = tonumber(v)
        end
      end
      table.insert(lines, line)
    end
  until line == ""

  local method = lines[1]:match("^(%S+)%s+(%S+)%s+(%S+)$")
  local method_lower = method:lower()

  local body
  if content_length then
    body = client:receive(content_length)

  elseif method_lower == "put" or method_lower == "post" then
    body = client:receive("*a")
  end

  local response_str
  local meta = getmetatable(response)
  if type(response) == "function" or (meta and meta.__call) then
    response_str = response(lines, body, headers)

  elseif type(response) == "table" and response.code then
    response_str = handle_response(response.code, response.body, response.headers)

  elseif type(response) == "table" and response[1] then
    response_str = handle_response(response[1], response[2], response[3])

  elseif type(response) == "string" then
    response_str = response

  elseif response == nil then
    response_str = "HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n"
  end


  client:send(response_str)
  return lines, body, headers
end


--- Start a local HTTP server with coroutine.
--
-- **DEPRECATED**: please use `spec.helpers.http_mock` instead.
--
-- local mock = helpers.http_mock(1234, { timeout = 0.1 })
-- wait for a request, and respond with the custom response
-- the request is returned as the function's return values
-- return nil, err if error
-- local lines, body, headers = mock(custom_response)
-- local lines, body, headers = mock()
-- mock("closing", true) -- close the server
local function http_mock(port, opts)
  local socket = require "socket"
  local server = assert(socket.tcp())
  if CONSTANTS.TEST_COVERAGE_MODE == "true" then
    opts.timeout = CONSTANTS.TEST_COVERAGE_TIMEOUT
  end
  server:settimeout(opts and opts.timeout or 60)
  assert(server:setoption('reuseaddr', true))
  assert(server:bind("*", port))
  assert(server:listen())
  return coroutine.wrap(function(response, exit)
    local lines, body, headers
    -- start listening
    while not exit do
      local client, err = server:accept()
      if err then
        lines, body = false, err

      else
        lines, body, headers = handle_request(client, response)
        client:close()
      end

      response, exit = coroutine.yield(lines, body, headers)
    end

    server:close()
    return true
  end)
end


--- Starts a local UDP server.
-- Reads the specified number of packets and then closes.
-- The server-thread return values depend on `n`:
--
-- * `n = 1`; returns the received packet (string), or `nil + err`
--
-- * `n > 1`; returns `data + err`, where `data` will always be a table with the
--   received packets. So `err` must explicitly be checked for errors.
-- @function udp_server
-- @tparam[opt] number port The port the server will be listening on, default: `MOCK_UPSTREAM_PORT`
-- @tparam[opt=1] number n The number of packets that will be read
-- @tparam[opt=360] number timeout Timeout per read (default 360)
-- @return A thread object (from the `llthreads2` Lua package)
local function udp_server(port, n, timeout)
  local threads = require "llthreads2.ex"

  if CONSTANTS.TEST_COVERAGE_MODE == "true" then
    timeout = CONSTANTS.TEST_COVERAGE_TIMEOUT
  end

  local thread = threads.new({
    function(port, n, timeout)
      local socket = require "socket"
      local server = assert(socket.udp())
      server:settimeout(timeout or 360)
      server:setoption("reuseaddr", true)
      server:setsockname("127.0.0.1", port)
      local err
      local data = {}
      local handshake_done = false
      local i = 0
      while i < n do
        local pkt, rport
        pkt, err, rport = server:receivefrom()
        if not pkt then
          break
        end
        if pkt == "KONG_UDP_HELLO" then
          if not handshake_done then
            handshake_done = true
            server:sendto("KONG_UDP_READY", "127.0.0.1", rport)
          end
        else
          i = i + 1
          data[i] = pkt
          err = nil -- upon succes it would contain the remote ip address
        end
      end
      server:close()
      return (n > 1 and data or data[1]), err
    end
  }, port or CONSTANTS.MOCK_UPSTREAM_PORT, n or 1, timeout)
  thread:start()

  local socket = require "socket"
  local handshake = socket.udp()
  handshake:settimeout(0.01)
  handshake:setsockname("127.0.0.1", 0)
  while true do
    handshake:sendto("KONG_UDP_HELLO", "127.0.0.1", port)
    local data = handshake:receive()
    if data == "KONG_UDP_READY" then
      break
    end
  end
  handshake:close()

  return thread
end


return {
  tcp_server = tcp_server,
  kill_tcp_server = kill_tcp_server,

  http_mock = http_mock,

  udp_server = udp_server,
}
