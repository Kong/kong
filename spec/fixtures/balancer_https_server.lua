#!/usr/bin/env resty

local ssl = require("ssl")
local cjson = require("cjson")
local socket = require("socket")

-- This is a "hard limit" for the execution of tests that launch
-- the custom http_server
local hard_timeout = ngx.now() + 300

local protocol = assert(arg[1])
local host = assert(arg[2])
local port = assert(arg[3])
local counts = assert(cjson.decode(arg[4]))
local TEST_LOG = arg[5] == "true"

local TIMEOUT = -1 -- luacheck: ignore

local function test_log(...) -- luacheck: ignore
  if not TEST_LOG then
    return
  end

  local t = {"server on port ", port, ": ", ...}
  for i, v in ipairs(t) do
    t[i] = tostring(v)
  end
  print(table.concat(t))
end


local total_reqs = 0
for _, c in pairs(counts) do
  total_reqs = total_reqs + (c < 0 and 1 or c)
end

local handshake_done = false
local fail_responses = 0
local ok_responses = 0
local reply_200 = true
local healthy = true
local n_checks = 0
local n_reqs = 0

local ssl_params = {
  mode = "server",
  protocol = "any",
  key = "spec/fixtures/kong_spec.key",
  certificate = "spec/fixtures/kong_spec.crt",
  verify = "peer",
  options = "all",
}

-- luasocket-based mock for http-only tests
-- not a real HTTP server, but runs faster
local sleep = socket.sleep
local httpserver = {
  listen = function(opts)
    local server = {}
    local sskt
    server.close = function()
      server.quit = true
    end
    server.loop = function(self)
      while not self.quit do
        local cskt, err = sskt:accept()

        if socket.gettime() > hard_timeout then
          if cskt then
            cskt:close()
          end
          break
        elseif err ~= "timeout" then
          if err then
            sskt:close()
            error(err)
          end

          if protocol == "https" then
            cskt = assert(ssl.wrap(cskt, ssl_params))
            local _, err = cskt:dohandshake()
            if err then
              error(err)
            end
          end

          local first, err = cskt:receive("*l")
          if first then
            opts.onstream(server, {
              get_path = function()
                return (first:match("(/[^%s]*)"))
              end,
              send_response = function(_, status, body)
                local r = status == 200 and "OK" or "Internal Server Error"
                local resp = {
                  "HTTP/1.1 " .. status .. " " .. r,
                  "Connection: Close",
                }
                if body then
                  table.insert(resp, "Content-length: " .. #body)
                end
                table.insert(resp, "")
                if body then
                  table.insert(resp, body)
                end
                table.insert(resp, "")
                test_log(table.concat(resp, "\r\n"))
                cskt:send(table.concat(resp, "\r\n"))
              end,
            })
          end
          cskt:close()
          if err and err ~= "closed" then
            sskt:close()
            error(err)
          end
        end
      end
      sskt:close()
    end
    local socket_fn = host:match(":") and socket.tcp6 or socket.tcp
    sskt = assert(socket_fn())
    assert(sskt:settimeout(0.1))
    assert(sskt:setoption('reuseaddr', true))
    assert(sskt:bind("*", opts.port))
    assert(sskt:listen())
    return server
  end,
}
local get_path = function(stream)
  return stream:get_path()
end
local send_response = function(stream, response, body)
  return stream:send_response(response, body)
end

local server = httpserver.listen({
  host = host:gsub("[%]%[]", ""),
  port = port,
  reuseaddr = true,
  v6only = host:match(":") ~= nil,
  onstream = function(self, stream)
    local path = get_path(stream)
    local status = 200
    local shutdown = false
    local body

    if path == "/handshake" then
      handshake_done = true

    elseif path == "/shutdown" then
      shutdown = true
      body = cjson.encode({
        ok_responses = ok_responses,
        fail_responses = fail_responses,
        n_checks = n_checks,
      })

    elseif path == "/status" then
      status = healthy and 200 or 500
      n_checks = n_checks + 1

    elseif path == "/healthy" then
      healthy = true

    elseif path == "/unhealthy" then
      healthy = false

    elseif handshake_done then
      n_reqs = n_reqs + 1
      test_log("nreqs ", n_reqs, " of ", total_reqs)

      while counts[1] == 0 do
        table.remove(counts, 1)
        reply_200 = not reply_200
      end
      if not counts[1] then
        error(host .. ":" .. port .. ": unexpected request")
      end
      if counts[1] == TIMEOUT then
        counts[1] = 0
        sleep(0.2)
      elseif counts[1] > 0 then
        counts[1] = counts[1] - 1
      end
      status = reply_200 and 200 or 500
      if status == 200 then
        ok_responses = ok_responses + 1
      else
        fail_responses = fail_responses + 1
      end

    else
      error("got a request before handshake was complete")
    end

    send_response(stream, status, body)

    if shutdown then
      self:close()
    end
  end,
})
test_log("starting")
server:loop()
test_log("stopped")
