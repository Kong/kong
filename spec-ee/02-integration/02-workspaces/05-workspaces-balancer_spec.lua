-- these tests only apply to the ring-balancer
-- for dns-record balancing see the `dns_spec` files

local helpers = require "spec.helpers"
local utils = require "kong.tools.utils"
local cjson = require "cjson"
local fmt = string.format

local FIRST_PORT = 20000
local SLOTS = 10
local HEALTHCHECK_INTERVAL = 0.01

local healthchecks_defaults = {
  active = {
    timeout = 1,
    concurrency = 10,
    http_path = "/",
    healthy = {
      interval = 0, -- 0 = disabled by default
      http_statuses = { 200, 302 },
      successes = 2,
    },
    unhealthy = {
      interval = 0, -- 0 = disabled by default
      http_statuses = { 429, 404,
                        500, 501, 502, 503, 504, 505 },
      tcp_failures = 2,
      timeouts = 3,
      http_failures = 5,
    },
  },
  passive = {
    healthy = {
      http_statuses = { 200, 201, 202, 203, 204, 205, 206, 207, 208, 226,
                        300, 301, 302, 303, 304, 305, 306, 307, 308 },
      successes = 5,
    },
    unhealthy = {
      http_statuses = { 429, 500, 503 },
      tcp_failures = 2,
      timeouts = 7,
      http_failures = 5,
    },
  },
}


local function healthchecks_config(config)
  return utils.deep_merge(healthchecks_defaults, config)
end


local TEST_LOG = false -- extra verbose logging of test server

local function direct_request(host, port, path)
  local pok, client = pcall(helpers.http_client, host, port)
  if not pok then
    return nil, "pcall: " .. client .. " : " .. host ..":"..port
  end
  if not client then
    return nil, "client"
  end
  local _, err = client:send {
    method = "GET",
    path = path,
    headers = { ["Host"] = "whatever" }
  }
  client:close()
  if err then
    return nil, err
  end
  return true
end


local function post_target_endpoint(upstream_name, host, port, endpoint, workspace)
  local url = "/upstreams/" .. upstream_name
    .. "/targets/"
    .. utils.format_host(host, port)
    .. "/" .. endpoint
  local path = fmt("%s%s", workspace and
    fmt("/%s", workspace) or "", url)
  local api_client = helpers.admin_client()
  local res, err = assert(api_client:send {
    method = "POST",
    path = path,
    headers = {
      ["Content-Type"] = "application/json",
    },
    body = {},
  })
  api_client:close()
  return res, err
end


-- Modified http-server. Accepts (sequentially) a number of incoming
-- connections and then rejects a given number of connections.
-- @param host Host name to use (IPv4 or IPv6 localhost).
-- @param port Port number to use.
-- @param counts Array of response counts to give,
-- odd entries are 200s, event entries are 500s
-- @param test_log (optional, default fals) Produce detailed logs
-- @return Returns the number of succesful and failure responses.
local function http_server(host, port, counts, test_log)

  -- This is a "hard limit" for the execution of tests that launch
  -- the custom http_server
  local hard_timeout = 300
  local expire = ngx.now() + hard_timeout

  local threads = require "llthreads2.ex"
  local thread = threads.new({
    function(expire, host, port, counts, TEST_LOG)
      local TIMEOUT = -1

      local function test_log(...)
        if not TEST_LOG then
          return
        end

        local t = {"server on port ", port, ": ", ...}
        for i, v in ipairs(t) do
          t[i] = tostring(v)
        end
        print(table.concat(t))
      end

      local socket = require "socket"
      local server
      if host:match(":") then
        server = assert(socket.tcp6())
      else
        server = assert(socket.tcp())
      end
      assert(server:setoption('reuseaddr', true))
      assert(server:bind("*", port))
      assert(server:listen())

      local handshake_done = false

      assert(server:settimeout(0.5))
      test_log("started")

      local healthy = true
      local n_checks = 0

      local ok_responses, fail_responses = 0, 0
      local total_reqs = 0
      for _, c in pairs(counts) do
        total_reqs = total_reqs + (c < 0 and 1 or c)
      end
      local n_reqs = 0
      local reply_200 = true
      while n_reqs < total_reqs + 1 do
        local client, err
        client, err = server:accept()
        if socket.gettime() > expire then
          if client then
            client:close()
          end
          break

        elseif not client then
          if err ~= "timeout" then
            server:close()
            error(err)
          end

        else
          local lines = {}
          local line, err
          while #lines < 7 do
            line, err = client:receive()
            if err or #line == 0 then
              break
            else
              table.insert(lines, line)
            end
          end
          if err and err ~= "closed" then
            client:close()
            server:close()
            error(err)
          end
          if #lines == 0 then
            goto continue
          end
          local got_handshake = lines[1] and lines[1]:match("/handshake")
          if got_handshake then
            client:send("HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n")
            handshake_done = true

          elseif lines[1]:match("/shutdown") then
            client:send("HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n")
            client:close()
            break

          elseif lines[1]:match("/status") then
            if healthy then
              client:send("HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n")
            else
              client:send("HTTP/1.1 500 Internal Server Error\r\nConnection: close\r\n\r\n")
            end
            n_checks = n_checks + 1

          elseif lines[1]:match("/healthy") then
            healthy = true
            client:send("HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n")

          elseif lines[1]:match("/unhealthy") then
            healthy = false
            client:send("HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n")

          elseif handshake_done and not got_handshake then
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
              socket.sleep(0.1)
            elseif counts[1] > 0 then
              counts[1] = counts[1] - 1
            end

            local response
            if reply_200 then
              response = "HTTP/1.1 200 OK"
            else
              response = "HTTP/1.1 500 Internal Server Error"
            end
            local sent = client:send(response .. "\r\nConnection: close\r\n\r\n")
            if sent then
              if reply_200 then
                ok_responses = ok_responses + 1
              else
                fail_responses = fail_responses + 1
              end
            end

          else
            client:close()
            server:close()
            error("got a request before the handshake was complete")
          end
          client:close()
          test_log(ok_responses, " oks, ", fail_responses," fails handled")
        end
        ::continue::
      end
      server:close()
      test_log("closed")
      return ok_responses, fail_responses, n_checks
    end
  }, expire, host, port, counts, test_log or TEST_LOG)

  local server = thread:start()

  repeat
    local _, err = direct_request(host, port, "/handshake")
    if err then
      ngx.sleep(0.01) -- poll-wait
    end
  until (ngx.now() > expire) or not err

  server.done = function(self)
    direct_request(host, port, "/shutdown")
    return self:join()
  end

  return server
end


local function client_requests(n, host_or_headers, proxy_host, proxy_port, protocol)
  local oks, fails = 0, 0
  local last_status
  for _ = 1, n do
    local client = (proxy_host and proxy_port)
                   and helpers.http_client(proxy_host, proxy_port)
                   or  helpers.proxy_client()

    if protocol == "https" then
      assert(client:ssl_handshake())
    end

    local res = client:send {
      method = "GET",
      path = "/",
      headers = type(host_or_headers) == "string"
                and { ["Host"] = host_or_headers }
                or host_or_headers
                or {}
    }
    if not res then
      fails = fails + 1
      if TEST_LOG then
        print("FAIL (no body)")
      end
    elseif res.status == 200 then
      oks = oks + 1
      if TEST_LOG then
        print("OK ", res.status, res:read_body())
      end
    elseif res.status > 399 then
      fails = fails + 1
      if TEST_LOG then
        print("FAIL ", res.status, res:read_body())
      end
    end
    last_status = res and res.status
    client:close()
  end
  return oks, fails, last_status
end


local add_upstream
local patch_upstream
local get_upstream_health
local add_target
local add_api
local patch_api
local gen_port
local create_workspace
local delete_workspace
local workspaces = {}

do
  local gen_sym
  do
    local sym = 0
    gen_sym = function(name)
      sym = sym + 1
      return name ..  "_" .. sym
    end
  end

  local function api_send(method, path, body)
    local api_client = helpers.admin_client()
    local res, err = api_client:send({
      method = method,
      path = path,
      headers = {
        ["Content-Type"] = "application/json"
      },
      body = body,
    })
    if not res then
      api_client:close()
      return nil, err
    end
    local res_body = res.status ~= 204 and cjson.decode((res:read_body()))
    api_client:close()
    return res.status, res_body
  end

  add_upstream = function(data, workspace)
    local path = fmt("%s/upstreams", workspace and
      fmt("/%s", workspace) or "")
    local upstream_name = gen_sym("upstream")
    local req = utils.deep_copy(data) or {}
    req.name = req.name or upstream_name
    req.slots = req.slots or SLOTS
    assert.same(201, api_send("POST", path, req))
    return req.name
  end

  patch_upstream = function(upstream_name, data, workspace)
    local path = fmt("%s/upstreams/%s", workspace and
      fmt("/%s", workspace) or "", upstream_name)
    assert.same(200, api_send("PATCH", path, data))
  end

  get_upstream_health = function(upstream_name, workspace)
    local path = fmt("%s/upstreams/%s/health", workspace and
      fmt("/%s", workspace) or "", upstream_name)
    local status, body = api_send("GET", path)
    if status == 200 then
      return body
    end
  end

  do
    local port = FIRST_PORT
    gen_port = function()
      port = port + 1
      return port
    end
  end

  add_target = function(upstream_name, host, port, data, workspace)
    port = port or gen_port()
    local req = utils.deep_copy(data) or {}
    req.target = req.target or utils.format_host(host, port)
    req.weight = req.weight or 10
    local path = fmt("%s/upstreams/%s/targets", workspace and
      fmt("/%s", workspace) or "", upstream_name)
    assert.same(201, api_send("POST", path, req))
    return port
  end

  add_api = function(upstream_name, read_timeout, write_timeout, connect_timeout, retries, workspace)
    local service_name = gen_sym("service")
    local route_host = gen_sym("host")
    local path = fmt("%s/services", workspace and
      fmt("/%s", workspace) or "")
    assert.same(201, api_send("POST", path, {
      name = service_name,
      url = "http://" .. upstream_name,
      read_timeout = read_timeout,
      write_timeout = write_timeout,
      connect_timeout = connect_timeout,
      retries = retries,
    }))
    path = fmt("%s/services/%s/routes", workspace and
      fmt("/%s", workspace) or "", service_name)
    assert.same(201, api_send("POST", path, {
      hosts = { route_host },
    }))
    return route_host, service_name
  end

  patch_api = function(service_name, new_upstream, workspace)
    local path = fmt("%s/services/%s", workspace and
      fmt("/%s", workspace) or "", service_name)
    assert.same(200, api_send("PATCH", path, {
      url = new_upstream
    }))
  end

  create_workspace = function(name)
    local path = "/workspaces"
    local body = {
      name = name
    }
    local api_client = helpers.admin_client()
    local res, err = api_client:send({
      method = "post",
      path = path,
      headers = {
        ["Content-Type"] = "application/json"
      },
      body = body,
    })
    if not res then
      api_client:close()
      return nil, err
    end
    local res_body = res.status ~= 204 and cjson.decode((res:read_body()))
    api_client:close()

    if res.status == 201 then
      workspaces[#workspaces + 1] = res_body
    end
    return res.status, res_body
  end
  delete_workspace = function(name)
    local path = "/workspaces/" .. name
    local api_client = helpers.admin_client()
    local res, err = api_client:send({
      method = "delete",
      path = path,
    })
    if not res then
      api_client:close()
      return nil, err
    end
    local res_body = res.status ~= 204 and cjson.decode((res:read_body()))
    api_client:close()
    return res.status, res_body
  end
end


local function delete_workspaces()
  for _, ws in ipairs(workspaces) do
    delete_workspace(ws.name)
  end
end


local function file_contains(filename, searched)
  local fd = assert(io.open(filename, "r"))
  for line in fd:lines() do
    if line:find(searched, 1, true) then
      fd:close()
      return true
    end
  end
  fd:close()
  return false
end


local function poll_wait_health(upstream_name, localhost, port, value, workspace)
  local hard_timeout = 300
  local expire = ngx.now() + hard_timeout
  while ngx.now() < expire do
    local health = get_upstream_health(upstream_name, workspace)
    if health then
      for _, d in ipairs(health.data) do
        if d.target == localhost .. ":" .. port and d.health == value then
          return
        end
      end
    end
    ngx.sleep(0.01) -- poll-wait
  end
end


local mode = "ipv4"
local localhost = "127.0.0.1"



for _, strategy in helpers.each_strategy() do
  workspaces = {}
  local teamA
  describe("Ring-balancer #" .. strategy, function()
    lazy_setup(function()
      helpers.get_db_utils(strategy)
      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        db_update_frequency = 0.1,
        stream_listen = "off",
        portal     = false,
      }))
      _, teamA = create_workspace("teamA")
    end)

    teardown(function()
      delete_workspaces()
      helpers.stop_kong()
      ngx.ctx.workspaces = nil
    end)

    describe("#healthchecks (#cluster)", function()

      lazy_setup(function()
        -- start a second Kong instance (ports are Kong test ports + 10)
        ngx.ctx.workspaces = nil
        assert(helpers.start_kong({
          database   = strategy,
          admin_gui_listen = "127.0.0.1:9012",
          admin_listen = "127.0.0.1:9011",
          proxy_listen = "127.0.0.1:9010",
          proxy_listen_ssl = "127.0.0.1:9453",
          admin_listen_ssl = "127.0.0.1:9454",
          stream_listen = "off",
          prefix = "servroot3",
          log_level = "debug",
          db_update_frequency = 0.1,
          portal     = false,
        }))
      end)

      teardown(function()
        helpers.stop_kong("servroot3", false, true)
      end)

      describe("#" .. mode, function()

        it("proxy with upstreams in different workspaces", function()

          local upstream_name = add_upstream({})
          local port = add_target(upstream_name, localhost)
          local api_host = add_api(upstream_name)

          local upstream_name_teamA = add_upstream({}, teamA.name)
          local port2 = add_target(upstream_name_teamA, localhost, nil, nil, teamA.name)
          local api_host_teamA = add_api(upstream_name_teamA, nil, nil, nil, nil, teamA.name)

          helpers.wait_until(function()
            return file_contains("servroot3/logs/error.log", "balancer:targets")
          end, 10)

          -- server responds, then fails, then responds again
          local server = http_server(localhost, port, { 20, 20, 20 })
          local server2 = http_server(localhost, port2, { 20, 20, 20 })

          local seq = {
            { port = 9000, oks = 10, fails = 0, last_status = 200 },
            { port = 9010, oks = 10, fails = 0, last_status = 200 },
            { port = 9000, oks = 0, fails = 10, last_status = 500 },
            { port = 9010, oks = 0, fails = 10, last_status = 500 },
            { port = 9000, oks = 10, fails = 0, last_status = 200 },
            { port = 9010, oks = 10, fails = 0, last_status = 200 },
          }
          for i, test in ipairs(seq) do
            local oks, fails, last_status = client_requests(10, api_host, "127.0.0.1", test.port)
            assert.same(test.oks, oks, "iteration " .. tostring(i))
            assert.same(test.fails, fails, "iteration " .. tostring(i))
            assert.same(test.last_status, last_status, "iteration " .. tostring(i))
          end

          -- collect server results
          local _, server_oks, server_fails = server:done()
          assert.same(40, server_oks)
          assert.same(20, server_fails)


          for i, test in ipairs(seq) do
            local oks, fails, last_status = client_requests(10, api_host_teamA, "127.0.0.1", test.port)
            assert.same(test.oks, oks, "iteration " .. tostring(i))
            assert.same(test.fails, fails, "iteration " .. tostring(i))
            assert.same(test.last_status, last_status, "iteration " .. tostring(i))
          end

          -- collect server results
          local _, server_oks, server_fails = server2:done()
          assert.same(40, server_oks)
          assert.same(20, server_fails)
        end)

        it("can create two upstreams in different workspace with same name", function()

          local upstream_name = add_upstream({
            name = "upstreeam_no_healthcheck"
          })
          local port = add_target(upstream_name, localhost)
          local api_host = add_api(upstream_name)

          local upstream_name_teamA = add_upstream({
            name = "upstreeam_no_healthcheck"
          }, teamA.name)
          local port2 = add_target(upstream_name_teamA, localhost, nil, nil, teamA.name)
          local api_host_teamA = add_api(upstream_name_teamA, nil, nil, nil, nil, teamA.name)

          ngx.sleep(2)

          -- server responds, then fails, then responds again
          local server = http_server(localhost, port, { 20, 20, 20 })
          local server2 = http_server(localhost, port2, { 20, 20, 20 })

          local seq = {
            { port = 9000, oks = 10, fails = 0, last_status = 200 },
            { port = 9010, oks = 10, fails = 0, last_status = 200 },
            { port = 9000, oks = 0, fails = 10, last_status = 500 },
            { port = 9010, oks = 0, fails = 10, last_status = 500 },
            { port = 9000, oks = 10, fails = 0, last_status = 200 },
            { port = 9010, oks = 10, fails = 0, last_status = 200 },
          }
          for i, test in ipairs(seq) do
            local oks, fails, last_status = client_requests(10, api_host, "127.0.0.1", test.port)
            assert.same(test.oks, oks, "iteration " .. tostring(i))
            assert.same(test.fails, fails, "iteration " .. tostring(i))
            assert.same(test.last_status, last_status, "iteration " .. tostring(i))
          end

          -- collect server results
          local _, server_oks, server_fails = server:done()
          assert.same(40, server_oks)
          assert.same(20, server_fails)


          for i, test in ipairs(seq) do
            local oks, fails, last_status = client_requests(10, api_host_teamA, "127.0.0.1", test.port)
            assert.same(test.oks, oks, "iteration " .. tostring(i))
            assert.same(test.fails, fails, "iteration " .. tostring(i))
            assert.same(test.last_status, last_status, "iteration " .. tostring(i))
          end

          -- collect server results
          local _, server_oks, server_fails = server2:done()
          assert.same(40, server_oks)
          assert.same(20, server_fails)
        end)
      end)
    end)

    describe("#" .. mode, function()

      describe("Upstream entities", function()

        -- Regression test for a missing invalidation in 0.12rc1
        it("created via the API are functional", function()
          local upstream_name = add_upstream()
          local target_port = add_target(upstream_name, localhost)
          local api_host = add_api(upstream_name)

          local server = http_server(localhost, target_port, { 1 })

          local oks, fails, last_status = client_requests(1, api_host)
          assert.same(200, last_status)
          assert.same(1, oks)
          assert.same(0, fails)

          local _, server_oks, server_fails = server:done()
          assert.same(1, server_oks)
          assert.same(0, server_fails)
        end)

        it("created via the API are functional in another workspace", function()
          local upstream_name = add_upstream({}, teamA.name)
          local target_port = add_target(upstream_name, localhost, nil, nil, teamA.name)
          local api_host = add_api(upstream_name, nil, nil, nil, nil, teamA.name)

          local server = http_server(localhost, target_port, { 1 })

          local oks, fails, last_status = client_requests(1, api_host)
          assert.same(200, last_status)
          assert.same(1, oks)
          assert.same(0, fails)

          local _, server_oks, server_fails = server:done()
          assert.same(1, server_oks)
          assert.same(0, server_fails)
        end)

        it("can be renamed without producing stale cache", function()
          -- create two upstreams, each with a target pointing to a server
          local upstreams = {}
          for i = 1, 2 do
            upstreams[i] = {}
            upstreams[i].name = add_upstream({
              healthchecks = healthchecks_config {}
            })
            upstreams[i].port = add_target(upstreams[i].name, localhost)
            upstreams[i].api_host = add_api(upstreams[i].name)
          end

          -- start two servers
          local server1 = http_server(localhost, upstreams[1].port, { 1 })
          local server2 = http_server(localhost, upstreams[2].port, { 1 })

          -- rename upstream 2
          local new_name = upstreams[2].name .. "_new"
          patch_upstream(upstreams[2].name, {
            name = new_name,
          })

          -- rename upstream 1 to upstream 2's original name
          patch_upstream(upstreams[1].name, {
            name = upstreams[2].name,
          })

          -- hit a request through upstream 1 using the new name
          local oks, fails, last_status = client_requests(1, upstreams[2].api_host)
          assert.same(200, last_status)
          assert.same(1, oks)
          assert.same(0, fails)

          -- rename upstream 2
          patch_upstream(new_name, {
            name = upstreams[1].name,
          })

          -- a single request to upstream 2 just to make server 2 shutdown
          client_requests(1, upstreams[1].api_host)

          -- collect results
          local _, server1_oks, server1_fails = server1:done()
          local _, server2_oks, server2_fails = server2:done()
          assert.same({1, 0}, { server1_oks, server1_fails })
          assert.same({1, 0}, { server2_oks, server2_fails })
        end)

        it("can be renamed without producing stale cache in another workspace", function()
          -- create two upstreams, each with a target pointing to a server
          local upstreams = {}
          for i = 1, 2 do
            upstreams[i] = {}
            upstreams[i].name = add_upstream({
              healthchecks = healthchecks_config {}
            }, teamA.name)
            upstreams[i].port = add_target(upstreams[i].name, localhost, nil, nil, teamA.name)
            upstreams[i].api_host = add_api(upstreams[i].name, nil, nil, nil, nil, teamA.name)
          end

          -- start two servers
          local server1 = http_server(localhost, upstreams[1].port, { 1 })
          local server2 = http_server(localhost, upstreams[2].port, { 1 })

          -- rename upstream 2
          local new_name = upstreams[2].name .. "_new"
          patch_upstream(upstreams[2].name, {
            name = new_name,
          }, teamA.name)

          -- rename upstream 1 to upstream 2's original name
          patch_upstream(upstreams[1].name, {
            name = upstreams[2].name,
          }, teamA.name)

          -- hit a request through upstream 1 using the new name
          local oks, fails, last_status = client_requests(1, upstreams[2].api_host)
          assert.same(200, last_status)
          assert.same(1, oks)
          assert.same(0, fails)

          -- rename upstream 2
          patch_upstream(new_name, {
            name = upstreams[1].name,
          }, teamA.name)

          -- a single request to upstream 2 just to make server 2 shutdown
          client_requests(1, upstreams[1].api_host)

          -- collect results
          local _, server1_oks, server1_fails = server1:done()
          local _, server2_oks, server2_fails = server2:done()
          assert.same({1, 0}, { server1_oks, server1_fails })
          assert.same({1, 0}, { server2_oks, server2_fails })
        end)

        it("do not leave a stale healthchecker when renamed", function()

          -- create an upstream
          local upstream_name = add_upstream({
            healthchecks = healthchecks_config {
              active = {
                http_path = "/status",
                healthy = {
                  interval = HEALTHCHECK_INTERVAL,
                  successes = 1,
                },
                unhealthy = {
                  interval = HEALTHCHECK_INTERVAL,
                  http_failures = 1,
                },
              }
            }
          })
          local port = add_target(upstream_name, localhost)
          local _, api_name = add_api(upstream_name)

          -- rename upstream
          local new_name = upstream_name .. "_new"
          patch_upstream(upstream_name, {
            name = new_name
          })

          -- reconfigure healthchecks
          patch_upstream(new_name, {
            healthchecks = {
              active = {
                http_path = "/status",
                healthy = {
                  interval = 0,
                  successes = 1,
                },
                unhealthy = {
                  interval = 0,
                  http_failures = 1,
                },
              }
            }
          })

          -- start server
          local server1 = http_server(localhost, port, { 1 })

          -- give time for healthchecker to (not!) run
          ngx.sleep(HEALTHCHECK_INTERVAL * 3)

          patch_api(api_name, "http://" .. new_name)

          -- collect results
          local _, server1_oks, server1_fails, hcs = server1:done()
          assert.same({0, 0}, { server1_oks, server1_fails })
          assert.truthy(hcs < 3)
        end)

        it("do not leave a stale healthchecker when renamed in another workspace", function()

          -- create an upstream
          local upstream_name = add_upstream({
            healthchecks = healthchecks_config {
              active = {
                http_path = "/status",
                healthy = {
                  interval = HEALTHCHECK_INTERVAL,
                  successes = 1,
                },
                unhealthy = {
                  interval = HEALTHCHECK_INTERVAL,
                  http_failures = 1,
                },
              }
            }
          }, teamA.name)
          local port = add_target(upstream_name, localhost, nil, nil, teamA.name)
          local _, api_name = add_api(upstream_name, nil, nil, nil, nil, teamA.name)

          -- rename upstream
          local new_name = upstream_name .. "_new"
          patch_upstream(upstream_name, {
            name = new_name
          }, teamA.name)

          -- reconfigure healthchecks
          patch_upstream(new_name, {
            healthchecks = {
              active = {
                http_path = "/status",
                healthy = {
                  interval = 0,
                  successes = 1,
                },
                unhealthy = {
                  interval = 0,
                  http_failures = 1,
                },
              }
            }
          }, teamA.name)

          -- start server
          local server1 = http_server(localhost, port, { 1 })

          -- give time for healthchecker to (not!) run
          ngx.sleep(HEALTHCHECK_INTERVAL * 100)

          patch_api(api_name, "http://" .. new_name, teamA.name)

          -- collect results
          local _, server1_oks, server1_fails, hcs = server1:done()
          assert.same({0, 0}, { server1_oks, server1_fails })
          assert.truthy(hcs < 3)
        end)

      end)

      describe("#healthchecks", function()

        it("perform passive health checks in non-default workspace", function()

          for nfails = 1, 3 do

            -- configure healthchecks
            local upstream_name = add_upstream({
              healthchecks = healthchecks_config {
                passive = {
                  unhealthy = {
                    http_failures = nfails,
                  }
                }
              }
            }, teamA.name)
            local port1 = add_target(upstream_name, localhost, nil, nil, teamA.name)
            local port2 = add_target(upstream_name, localhost, nil, nil, teamA.name)
            local api_host = add_api(upstream_name, nil, nil, nil, nil, teamA.name)

            local requests = SLOTS * 2 -- go round the balancer twice

            -- setup target servers:
            -- server2 will only respond for part of the test,
            -- then server1 will take over.
            local server2_oks = math.floor(requests / 4)
            local server1 = http_server(localhost, port1, {
              requests - server2_oks - nfails
            })
            local server2 = http_server(localhost, port2, {
              server2_oks,
              nfails
            })

            -- Go hit them with our test requests
            local client_oks, client_fails = client_requests(requests, api_host)

            -- collect server results; hitcount
            local _, ok1, fail1 = server1:done()
            local _, ok2, fail2 = server2:done()

            -- verify
            assert.are.equal(requests - server2_oks - nfails, ok1)
            assert.are.equal(server2_oks, ok2)
            assert.are.equal(0, fail1)
            assert.are.equal(nfails, fail2)

            assert.are.equal(requests - nfails, client_oks)
            assert.are.equal(nfails, client_fails)
          end
        end)

        it("perform active health checks with same upstream name in different workspace", function()

          local requests = SLOTS * 2 -- go round the balancer twice
          local port1 = gen_port()
          local port2 = gen_port()

          local server1 = http_server(localhost, port1, { requests })
          local server2 = http_server(localhost, port2, { requests })

          -- configure healthchecks
          local upstream_name_default = add_upstream({
            name = "upstream-same-name",
            healthchecks = healthchecks_config {
              active = {
                http_path = "/status",
                healthy = {
                  interval = HEALTHCHECK_INTERVAL,
                  successes = 1,
                },
                unhealthy = {
                  interval = HEALTHCHECK_INTERVAL,
                  http_failures = 1,
                },
              }
            }
          })
          add_target(upstream_name_default, localhost, port1)
          local api_host_default = add_api(upstream_name_default)

          local upstream_name_teamA = add_upstream({
            name = "upstream-same-name",
            healthchecks = healthchecks_config {
              active = {
                http_path = "/status",
                healthy = {
                  interval = HEALTHCHECK_INTERVAL,
                  successes = 1,
                },
                unhealthy = {
                  interval = HEALTHCHECK_INTERVAL,
                  http_failures = 1,
                },
              }
            }
          }, teamA.name)
          add_target(upstream_name_teamA, localhost, port2, nil, teamA.name)
          local api_host_teamA = add_api(upstream_name_teamA, nil, nil, nil, nil, teamA.name)

          client_requests(requests, api_host_default)
          client_requests(requests, api_host_teamA)

          -- collect server results; hitcount
          local _, ok1, fail1 = server1:done()
          local _, ok2, fail2 = server2:done()

          -- verify
          assert.are.equal(requests, ok1)
          assert.are.equal(requests, ok2)
          assert.are.equal(0, fail1)
          assert.are.equal(0, fail2)
        end)

        it("perform active health checks -- up then down in non-default workspace", function()

          for nfails = 1, 3 do

            local requests = SLOTS * 2 -- go round the balancer twice
            local port1 = gen_port()
            local port2 = gen_port()

            -- setup target servers:
            -- server2 will only respond for part of the test,
            -- then server1 will take over.
            local server2_oks = math.floor(requests / 4)
            local server1 = http_server(localhost, port1, { requests - server2_oks })
            local server2 = http_server(localhost, port2, { server2_oks })

            -- configure healthchecks
            local upstream_name = add_upstream({
              healthchecks = healthchecks_config {
                active = {
                  http_path = "/status",
                  healthy = {
                    interval = HEALTHCHECK_INTERVAL,
                    successes = 1,
                  },
                  unhealthy = {
                    interval = HEALTHCHECK_INTERVAL,
                    http_failures = nfails,
                  },
                }
              }
            }, teamA.name)
            add_target(upstream_name, localhost, port1, nil, teamA.name)
            add_target(upstream_name, localhost, port2, nil, teamA.name)
            local api_host = add_api(upstream_name, nil, nil, nil, nil, teamA.name)

            -- Phase 1: server1 and server2 take requests
            local client_oks, client_fails = client_requests(server2_oks * 2, api_host)

            -- Phase 2: server2 goes unhealthy
            direct_request(localhost, port2, "/unhealthy")

            -- Give time for healthchecker to detect
            poll_wait_health(upstream_name, localhost, port2, "UNHEALTHY", teamA.name)

            -- Phase 3: server1 takes all requests
            do
              local p3oks, p3fails = client_requests(requests - (server2_oks * 2), api_host)
              client_oks = client_oks + p3oks
              client_fails = client_fails + p3fails
            end

            -- collect server results; hitcount
            local _, ok1, fail1 = server1:done()
            local _, ok2, fail2 = server2:done()

            -- verify
            assert.are.equal(requests - server2_oks, ok1)
            assert.are.equal(server2_oks, ok2)
            assert.are.equal(0, fail1)
            assert.are.equal(0, fail2)

            assert.are.equal(requests, client_oks)
            assert.are.equal(0, client_fails)
          end
        end)

        it("perform active health checks -- automatic recovery in non-default workspace", function()

          for nchecks = 1, 3 do

            local port1 = gen_port()
            local port2 = gen_port()

            -- setup target servers:
            -- server2 will only respond for part of the test,
            -- then server1 will take over.
            local server1_oks = SLOTS * 2
            local server2_oks = SLOTS
            local server1 = http_server(localhost, port1, { server1_oks })
            local server2 = http_server(localhost, port2, { server2_oks })

            -- configure healthchecks
            local upstream_name = add_upstream({
              healthchecks = healthchecks_config {
                active = {
                  http_path = "/status",
                  healthy = {
                    interval = HEALTHCHECK_INTERVAL,
                    successes = nchecks,
                  },
                  unhealthy = {
                    interval = HEALTHCHECK_INTERVAL,
                    http_failures = nchecks,
                  },
                }
              }
            }, teamA.name)
            add_target(upstream_name, localhost, port1, nil, teamA.name)
            add_target(upstream_name, localhost, port2, nil, teamA.name)
            local api_host = add_api(upstream_name, nil, nil, nil, nil, teamA.name)

            -- 1) server1 and server2 take requests
            local oks, fails = client_requests(SLOTS, api_host)

            -- server2 goes unhealthy
            direct_request(localhost, port2, "/unhealthy")
            -- Wait until healthchecker detects
            poll_wait_health(upstream_name, localhost, port2, "UNHEALTHY", teamA.name)

            -- 2) server1 takes all requests
            do
              local o, f = client_requests(SLOTS, api_host)
              oks = oks + o
              fails = fails + f
            end

            -- server2 goes healthy again
            direct_request(localhost, port2, "/healthy")
            -- Give time for healthchecker to detect
            poll_wait_health(upstream_name, localhost, port2, "HEALTHY", teamA.name)

            -- 3) server1 and server2 take requests again
            do
              local o, f = client_requests(SLOTS, api_host)
              oks = oks + o
              fails = fails + f
            end

            -- collect server results; hitcount
            local _, ok1, fail1 = server1:done()
            local _, ok2, fail2 = server2:done()

            -- verify
            assert.are.equal(SLOTS * 2, ok1)
            assert.are.equal(SLOTS, ok2)
            assert.are.equal(0, fail1)
            assert.are.equal(0, fail2)

            assert.are.equal(SLOTS * 3, oks)
            assert.are.equal(0, fails)
          end
        end)

        it("perform active health checks -- can detect before any proxy traffic in non-default workspace", function()

          local nfails = 2
          local requests = SLOTS * 2 -- go round the balancer twice
          local port1 = gen_port()
          local port2 = gen_port()
          -- setup target servers:
          -- server1 will respond all requests
          local server1 = http_server(localhost, port1, { requests })
          local server2 = http_server(localhost, port2, { requests })
          -- configure healthchecks
          local upstream_name = add_upstream({
            healthchecks = healthchecks_config {
              active = {
                http_path = "/status",
                healthy = {
                  interval = HEALTHCHECK_INTERVAL,
                  successes = 1,
                },
                unhealthy = {
                  interval = HEALTHCHECK_INTERVAL,
                  http_failures = nfails,
                  tcp_failures = nfails,
                },
              }
            }
          }, teamA.name)
          add_target(upstream_name, localhost, port1, nil, teamA.name)
          add_target(upstream_name, localhost, port2, nil, teamA.name)
          local api_host = add_api(upstream_name, nil, nil, nil, nil, teamA.name)

          -- server2 goes unhealthy before the first request
          direct_request(localhost, port2, "/unhealthy")

          -- restart Kong
          helpers.stop_kong(nil, true, true)
          helpers.start_kong({
            database   = strategy,
            nginx_conf = "spec/fixtures/custom_nginx.template",
            db_update_frequency = 0.1,
          })

          -- Give time for healthchecker to detect
          poll_wait_health(upstream_name, localhost, port2, "UNHEALTHY", teamA.name)

          -- server1 takes all requests
          local client_oks, client_fails = client_requests(requests, api_host)

          -- collect server results; hitcount
          local _, ok1, fail1 = server1:done()
          local _, ok2, fail2 = server2:done()

          -- verify
          assert.are.equal(requests, ok1)
          assert.are.equal(0, ok2)
          assert.are.equal(0, fail1)
          assert.are.equal(0, fail2)

          assert.are.equal(requests, client_oks)
          assert.are.equal(0, client_fails)

        end)

        it("perform passive health checks -- manual shutdown in non-defaault workspace", function()

          -- configure healthchecks
          local upstream_name = add_upstream({
            healthchecks = healthchecks_config {
              passive = {
                unhealthy = {
                  http_failures = 1,
                }
              }
            }
          }, teamA.name)
          local port1 = add_target(upstream_name, localhost, nil, nil, teamA.name)
          local port2 = add_target(upstream_name, localhost, nil, nil, teamA.name)
          local api_host = add_api(upstream_name, nil, nil, nil, nil, teamA.name)

          -- setup target servers:
          -- server2 will only respond for part of the test,
          -- then server1 will take over.
          local server1_oks = SLOTS * 2
          local server2_oks = SLOTS
          local server1 = http_server(localhost, port1, { server1_oks })
          local server2 = http_server(localhost, port2, { server2_oks })

          -- 1) server1 and server2 take requests
          local oks, fails = client_requests(SLOTS, api_host)

          -- manually bring it down using the endpoint
          post_target_endpoint(upstream_name, localhost, port2, "unhealthy", teamA.name)

          -- 2) server1 takes all requests
          do
            local o, f = client_requests(SLOTS, api_host)
            oks = oks + o
            fails = fails + f
          end

          -- manually bring it back using the endpoint
          post_target_endpoint(upstream_name, localhost, port2, "healthy", teamA.name)

          -- 3) server1 and server2 take requests again
          do
            local o, f = client_requests(SLOTS, api_host)
            oks = oks + o
            fails = fails + f
          end

          -- collect server results; hitcount
          local _, ok1, fail1 = server1:done()
          local _, ok2, fail2 = server2:done()

          -- verify
          assert.are.equal(SLOTS * 2, ok1)
          assert.are.equal(SLOTS, ok2)
          assert.are.equal(0, fail1)
          assert.are.equal(0, fail2)

          assert.are.equal(SLOTS * 3, oks)
          assert.are.equal(0, fails)

        end)

      end)

      describe("Balancing in non-default workspace", function()

        describe("with round-robin", function()

          it("over multiple targets", function()

            local upstream_name = add_upstream(nil, teamA.name)
            local port1 = add_target(upstream_name, localhost, nil, nil, teamA.name)
            local port2 = add_target(upstream_name, localhost, nil, nil, teamA.name)
            local api_host = add_api(upstream_name, nil, nil, nil, nil, teamA.name)

            local requests = SLOTS * 2 -- go round the balancer twice

            -- setup target servers
            local server1 = http_server(localhost, port1, { requests / 2 })
            local server2 = http_server(localhost, port2, { requests / 2 })

            -- Go hit them with our test requests
            local oks = client_requests(requests, api_host)
            assert.are.equal(requests, oks)

            -- collect server results; hitcount
            local _, count1 = server1:done()
            local _, count2 = server2:done()

            -- verify
            assert.are.equal(requests / 2, count1)
            assert.are.equal(requests / 2, count2)
          end)

          it("adding a target", function()

            local upstream_name = add_upstream(nil, teamA.name)
            local port1 = add_target(upstream_name, localhost, nil, { weight = 10 }, teamA.name)
            local port2 = add_target(upstream_name, localhost, nil, { weight = 10 }, teamA.name)
            local api_host = add_api(upstream_name, nil, nil, nil, nil, teamA.name)

            local requests = SLOTS * 2 -- go round the balancer twice

            -- setup target servers
            local server1 = http_server(localhost, port1, { requests / 2 })
            local server2 = http_server(localhost, port2, { requests / 2 })

            -- Go hit them with our test requests
            local oks = client_requests(requests, api_host)
            assert.are.equal(requests, oks)

            -- collect server results; hitcount
            local _, count1 = server1:done()
            local _, count2 = server2:done()

            -- verify
            assert.are.equal(requests / 2, count1)
            assert.are.equal(requests / 2, count2)

            -- add a new target 3
            -- shift proportions from 50/50 to 40/40/20
            local port3 = add_target(upstream_name, localhost, nil, { weight = 5 }, teamA.name)

            -- now go and hit the same balancer again
            -----------------------------------------

            -- setup target servers
            local server3
            server1 = http_server(localhost, port1, { requests * 0.4 })
            server2 = http_server(localhost, port2, { requests * 0.4 })
            server3 = http_server(localhost, port3, { requests * 0.2 })

            -- Go hit them with our test requests
            oks = client_requests(requests, api_host)
            assert.are.equal(requests, oks)

            -- collect server results; hitcount
            _, count1 = server1:done()
            _, count2 = server2:done()
            local _, count3 = server3:done()

            -- verify
            assert.are.equal(requests * 0.4, count1)
            assert.are.equal(requests * 0.4, count2)
            assert.are.equal(requests * 0.2, count3)
          end)

          it("removing a target", function()
            local requests = SLOTS * 2 -- go round the balancer twice

            local upstream_name = add_upstream(nil, teamA.name)
            local port1 = add_target(upstream_name, localhost, nil, nil, teamA.name)
            local port2 = add_target(upstream_name, localhost, nil, nil, teamA.name)
            local api_host = add_api(upstream_name, nil, nil, nil, nil, teamA.name)

            -- setup target servers
            local server1 = http_server(localhost, port1, { requests / 2 })
            local server2 = http_server(localhost, port2, { requests / 2 })

            -- Go hit them with our test requests
            local oks = client_requests(requests, api_host)
            assert.are.equal(requests, oks)

            -- collect server results; hitcount
            local _, count1 = server1:done()
            local _, count2 = server2:done()

            -- verify
            assert.are.equal(requests / 2, count1)
            assert.are.equal(requests / 2, count2)

            -- modify weight for target 2, set to 0
            add_target(upstream_name, localhost, port2, {
              weight = 0, -- disable this target
            }, teamA.name)

            -- now go and hit the same balancer again
            -----------------------------------------

            -- setup target servers
            server1 = http_server(localhost, port1, { requests })

            -- Go hit them with our test requests
            oks = client_requests(requests, api_host)
            assert.are.equal(requests, oks)

            -- collect server results; hitcount
            _, count1 = server1:done()

            -- verify all requests hit server 1
            assert.are.equal(requests, count1)
          end)

        end)

        describe("with consistent hashing in non-default workspace", function()

          it("over multiple targets", function()
            local requests = SLOTS * 2 -- go round the balancer twice

            local upstream_name = add_upstream({
              hash_on = "header",
              hash_on_header = "hashme",
            }, teamA.name)
            local port1 = add_target(upstream_name, localhost, nil, nil, teamA.name)
            local port2 = add_target(upstream_name, localhost, nil, nil, teamA.name)
            local api_host = add_api(upstream_name, nil, nil, nil, nil, teamA.name)

            -- setup target servers
            local server1 = http_server(localhost, port1, { requests })
            local server2 = http_server(localhost, port2, { requests })

            -- Go hit them with our test requests
            local oks = client_requests(requests, {
              ["Host"] = api_host,
              ["hashme"] = "just a value",
            })
            assert.are.equal(requests, oks)

            -- collect server results; hitcount
            -- one should get all the hits, the other 0
            local _, count1 = server1:done()
            local _, count2 = server2:done()

            -- verify
            assert(count1 == 0 or count1 == requests, "counts should either get 0 or ALL hits")
            assert(count2 == 0 or count2 == requests, "counts should either get 0 or ALL hits")
            assert(count1 + count2 == requests)
          end)

        end)

        describe("with no targets", function()

          it("failure due to no targets", function()

            local upstream_name = add_upstream(nil, teamA.name)
            local api_host = add_api(upstream_name, nil, nil, nil, nil, teamA.name)

            -- Go hit it with a request
            local _, _, status = client_requests(1, api_host)
            assert.same(503, status)

          end)

        end)
      end)
    end)
  end)
end -- for each_strategy
