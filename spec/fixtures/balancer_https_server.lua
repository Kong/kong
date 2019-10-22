#!/usr/bin/env resty

local ssl = require("ssl")
local cjson = require("cjson")
local socket = require("socket")

-- This is a "hard limit" for the execution of tests that launch
-- the custom http_server
local hard_timeout = ngx.now() + 300

local protocol = assert(arg[1])
local host_or_ip = assert(arg[2])
local port = assert(arg[3])
local total_counts = assert(cjson.decode(arg[4]))
local TEST_LOG = arg[5] == "true"
local check_hostname = arg[6] == "true"

local TIMEOUT = -1 -- luacheck: ignore
local status_messages = {
  [200] = "OK",
  [400] = "Bad Request",
  [500] = "Internal Server Error",
}

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
    server.host_or_ip = opts.host_or_ip
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

          local headers = {}
          local path
          while true do
            local line, err = cskt:receive("*l")
            if err and err == "closed" then
              break

            elseif not path then
              path = line:match("(/[^%s]*)")

            elseif line and not line:match("^%s*$") then
              local k, v = line:match("^%s*([^%s]+)%s*:%s*(.-)%s*$")
              headers[k:lower()] = v

            else
              opts.onstream(server, {
                get_path = function()
                  return path
                end,
                get_header = function(_, k)
                  return headers[k]
                end,
                send_response = function(_, status, body)
                  local resp = {
                    "HTTP/1.1 " .. status .. " " .. status_messages[status],
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
                  cskt:send(table.concat(resp, "\r\n"))
                end,
              })
              break
            end
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
    local socket_fn = host_or_ip:match(":") and socket.tcp6 or socket.tcp
    sskt = assert(socket_fn())
    assert(sskt:settimeout(0.1))
    assert(sskt:setoption('reuseaddr', true))
    assert(sskt:bind("*", opts.port))
    assert(sskt:listen())
    return server
  end,
}


local handshake_done = false
local host_data = {}


local function get_host_data(host)
  if not host_data[host] then
    host_data[host] = {
      fail_responses = 0,
      ok_responses = 0,
      reply_200 = true,
      healthy = true,
      n_checks = 0,
      n_reqs = 0,
    }
  end
  return host_data[host]
end


local server = httpserver.listen({
  host_or_ip = host_or_ip:gsub("[%]%[]", ""),
  port = port,
  reuseaddr = true,
  v6only = host_or_ip:match(":") ~= nil,
  onstream = function(self, stream)
    local header_host = stream:get_header("host"):gsub(":[0-9]+$", "")
    local host = (stream:get_header("host") or self.host_or_ip):gsub(":[0-9]+$", "")
    local path = stream:get_path()
    local status = 200
    local shutdown = false
    local body

    local data = get_host_data(host)

    if path == "/handshake" then
      handshake_done = true

    elseif path == "/shutdown" then
      shutdown = true
      body = cjson.encode({
        ok_responses = data.ok_responses,
        fail_responses = data.fail_responses,
        n_checks = data.n_checks,
      })

    elseif path == "/results" then
      body = cjson.encode({
        ok_responses = data.ok_responses,
        fail_responses = data.fail_responses,
        n_checks = data.n_checks,
      })

    elseif path == "/status" then
      if not check_hostname or header_host == self.host_or_ip then
        status = data.healthy and 200 or 500
      else
        test_log("hostname check fail in /status")
        status = 400
      end
      data.n_checks = data.n_checks + 1

    elseif path == "/healthy" then
      data.healthy = true

    elseif path == "/unhealthy" then
      data.healthy = false

    elseif handshake_done then
      data.n_reqs = data.n_reqs + 1
      test_log("nreqs ", data.n_reqs)

      if not check_hostname or header_host == self.host_or_ip then
        local counts = total_counts[1] and total_counts or total_counts[host]
        while counts[1] == 0 do
          table.remove(counts, 1)
          data.reply_200 = not data.reply_200
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
        status = data.reply_200 and 200 or 500
      else
        test_log("hostname check fail")
        status = 400
      end
      if status == 200 then
        data.ok_responses = data.ok_responses + 1
      else
        data.fail_responses = data.fail_responses + 1
      end

    else
      error("got a request before handshake was complete")
    end

    stream:send_response(status, body)

    if shutdown then
      self:close()
    end
  end,
})
test_log("starting")
server:loop()
test_log("stopped")
