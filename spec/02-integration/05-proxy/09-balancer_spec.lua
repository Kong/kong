-- these tests only apply to the ring-balancer
-- for dns-record balancing see the `dns_spec` files

local helpers = require "spec.helpers"
local utils = require "kong.tools.utils"
local cjson = require "cjson"

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


local TIMEOUT = -1  -- marker for timeouts in http_server


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


local function post_target_endpoint(upstream_name, host, port, endpoint)
  local url = "/upstreams/" .. upstream_name
                            .. "/targets/"
                            .. utils.format_host(host, port)
                            .. "/" .. endpoint
  local api_client = helpers.admin_client()
  local res, err = assert(api_client:send {
    method = "POST",
    path = url,
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
local function http_server(host, port, counts, test_log, protocol)

  -- This is a "hard limit" for the execution of tests that launch
  -- the custom http_server
  local hard_timeout = 300
  local expire = ngx.now() + hard_timeout

  local threads = require "llthreads2.ex"
  local thread = threads.new({
    function(expire, host, port, counts, TEST_LOG, protocol) -- luacheck: ignore
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

      local httpserver, get_path, send_response, sleep, sslctx
      if protocol == "https" then
        -- lua-http server for http+https tests
        local cqueues = require "cqueues"
        sleep = cqueues.sleep
        httpserver = require "http.server"
        local openssl_pkey = require "openssl.pkey"
        local openssl_x509 = require "openssl.x509"
        get_path = function(stream)
          local headers = assert(stream:get_headers(60))
          return headers:get(":path")
        end
        local httpheaders = require "http.headers"
        send_response = function(stream, response)
          local rh = httpheaders.new()
          rh:upsert(":status", tostring(response))
          rh:upsert("connection", "close")
          assert(stream:write_headers(rh, false))
        end
        sslctx = require("http.tls").new_server_context()
        local fd = io.open("spec/fixtures/kong_spec.key", "r")
        local pktext = fd:read("*a")
        fd:close()
        local pk = assert(openssl_pkey.new(pktext))
        assert(sslctx:setPrivateKey(pk))
        fd = io.open("spec/fixtures/kong_spec.crt", "r")
        local certtext = fd:read("*a")
        fd:close()
        local cert = assert(openssl_x509.new(certtext))
        assert(sslctx:setCertificate(cert))
      else
        -- luasocket-based mock for http-only tests
        -- not a real HTTP server, but runs faster
        local socket = require "socket"
        sleep = socket.sleep
        httpserver = {
          listen = function(opts)
            local server = {}
            local sskt
            server.close = function()
              server.quit = true
            end
            server.loop = function(self)
              while not self.quit do
                local cskt, err = sskt:accept()
                if socket.gettime() > expire then
                  cskt:close()
                  break
                elseif err ~= "timeout" then
                  if err then
                    sskt:close()
                    error(err)
                  end
                  local first, err = cskt:receive("*l")
                  if first then
                    opts.onstream(server, {
                      get_path = function()
                        return (first:match("(/[^%s]*)"))
                      end,
                      send_response = function(_, response)
                        local r = response == 200 and "OK" or "Internal Server Error"
                        cskt:send("HTTP/1.1 " .. response .. " " .. r ..
                                  "\r\nConnection: close\r\n\r\n")
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
        get_path = function(stream)
          return stream:get_path()
        end
        send_response = function(stream, response)
          return stream:send_response(response)
        end
      end

      local server = httpserver.listen({
        host = host:gsub("[%]%[]", ""),
        port = port,
        reuseaddr = true,
        v6only = host:match(":") ~= nil,
        ctx = sslctx,
        onstream = function(self, stream)
          local path = get_path(stream)
          local response = 200
          local shutdown = false

          if path == "/handshake" then
            handshake_done = true

          elseif path == "/shutdown" then
            shutdown = true

          elseif path == "/status" then
            response = healthy and 200 or 500
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
            response = reply_200 and 200 or 500
            if response == 200 then
              ok_responses = ok_responses + 1
            else
              fail_responses = fail_responses + 1
            end

          else
            error("got a request before handshake was complete")
          end

          send_response(stream, response)

          if shutdown then
            self:close()
          end
        end,
      })
      test_log("starting")
      server:loop()
      test_log("stopped")
      return ok_responses, fail_responses, n_checks
    end
  }, expire, host, port, counts, test_log or TEST_LOG, protocol)

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


local function client_requests(n, host_or_headers, proxy_host, proxy_port)
  local oks, fails = 0, 0
  local last_status
  for _ = 1, n do
    local client = (proxy_host and proxy_port)
                   and helpers.http_client(proxy_host, proxy_port)
                   or  helpers.proxy_client()
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
local get_upstream
local get_upstream_health
local get_router_version
local add_target
local add_api
local patch_api
local delete_api
local add_plugin
local delete_plugin
local gen_port
do
  local gen_sym
  do
    local sym = 0
    gen_sym = function(name)
      sym = sym + 1
      return name .. "_" .. sym
    end
  end

  local function api_send(method, path, body, forced_port)
    local api_client = helpers.admin_client(nil, forced_port)
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

  add_upstream = function(data, name)
    local upstream_name = name or gen_sym("upstream")
    if TEST_LOG then
      print("ADDING UPSTREAM ", upstream_name)
    end
    local req = utils.deep_copy(data) or {}
    req.name = req.name or upstream_name
    req.slots = req.slots or SLOTS
    assert.same(201, api_send("POST", "/upstreams", req))
    return upstream_name
  end

  patch_upstream = function(upstream_name, data)
    assert.same(200, api_send("PATCH", "/upstreams/" .. upstream_name, data))
  end

  get_upstream = function(upstream_name, forced_port)
    local path = "/upstreams/" .. upstream_name
    local status, body = api_send("GET", path, nil, forced_port)
    if status == 200 then
      return body
    end
  end

  get_upstream_health = function(upstream_name, forced_port)
    local path = "/upstreams/" .. upstream_name .."/health"
    local status, body = api_send("GET", path, nil, forced_port)
    if status == 200 then
      return body
    end
  end

  get_router_version = function(forced_port)
    local path = "/cache/router:version"
    local status, body = api_send("GET", path, nil, forced_port)
    if status == 200 then
      return body.message
    end
  end

  do
    local port = FIRST_PORT
    gen_port = function()
      port = port + 1
      return port
    end
  end

  add_target = function(upstream_name, host, port, data)
    port = port or gen_port()
    local req = utils.deep_copy(data) or {}
    req.target = req.target or utils.format_host(host, port)
    req.weight = req.weight or 10
    local path = "/upstreams/" .. upstream_name .. "/targets"
    assert.same(201, api_send("POST", path, req))
    return port
  end

  add_api = function(upstream_name, read_timeout, write_timeout, connect_timeout, retries, protocol)
    local service_name = gen_sym("service")
    local route_host = gen_sym("host")
    assert.same(201, api_send("POST", "/services", {
      name = service_name,
      url = (protocol or "http") .. "://" .. upstream_name .. ":" .. (protocol == "tcp" and 9100 or 80),
      read_timeout = read_timeout,
      write_timeout = write_timeout,
      connect_timeout = connect_timeout,
      retries = retries,
      protocol = protocol,
    }))
    local path = "/services/" .. service_name .. "/routes"
    local status, res = api_send("POST", path, {
      protocols = { protocol or "http" },
      hosts = protocol ~= "tcp" and { route_host } or nil,
      destinations = (protocol == "tcp") and {{ port = 9100 }} or nil,
    })
    assert.same(201, status)
    return route_host, service_name, res.id
  end

  patch_api = function(service_name, new_upstream, read_timeout)
    assert.same(200, api_send("PATCH", "/services/" .. service_name, {
      url = new_upstream,
      read_timeout = read_timeout,
    }))
  end

  add_plugin = function(service_name, body)
    local path = "/services/" .. service_name .. "/plugins"
    local status, plugin = assert(api_send("POST", path, body))
    assert.same(status, 201)
    return plugin.id
  end

  delete_plugin = function(service_name, plugin_id)
    local path = "/plugins/" .. plugin_id
    assert.same(204, api_send("DELETE", path, {}))
  end

  delete_api = function(service_name, route_id)
    local path = "/routes/" .. route_id
    assert.same(204, api_send("DELETE", path, {}))
    path = "/services/" .. service_name
    assert.same(204, api_send("DELETE", path, {}))
  end
end


local function truncate_relevant_tables(db, dao)
  db:truncate("services")
  db:truncate("routes")
  db:truncate("upstreams")
  db:truncate("targets")
  dao.plugins:truncate()
end


local function poll_wait_health(upstream_name, host, port, value, admin_port)
  local hard_timeout = 300
  local expire = ngx.now() + hard_timeout
  while ngx.now() < expire do
    local health = get_upstream_health(upstream_name, admin_port)
    if health then
      for _, d in ipairs(health.data) do
        if d.target == host .. ":" .. port and d.health == value then
          return
        end
      end
    end
    ngx.sleep(0.01) -- poll-wait
  end
  assert(false, "timed out waiting for " .. host .. ":" .. port .. " in " ..
                upstream_name .. " to become " .. value)
end


local function wait_for_router_update(old_rv, localhost, proxy_port, admin_port)
  -- add dummy upstream just to rebuild router
  local dummy_upstream_name = add_upstream()
  local dummy_port = add_target(dummy_upstream_name, localhost)
  local dummy_api_host = add_api(dummy_upstream_name)
  local dummy_server = http_server(localhost, dummy_port, { 1000 })

  helpers.wait_until(function()
    client_requests(1, dummy_api_host, "127.0.0.1", proxy_port)
    local rv = get_router_version(admin_port)
    return rv ~= old_rv
  end, 5)

  dummy_server:done()
end


local localhosts = {
  ipv4 = "127.0.0.1",
  ipv6 = "[0000:0000:0000:0000:0000:0000:0000:0001]",
  hostname = "localhost",
}


for _, strategy in helpers.each_strategy() do

  describe("Ring-balancer #" .. strategy, function()

    lazy_setup(function()
      local _, db, dao = helpers.get_db_utils(strategy, {})

      truncate_relevant_tables(db, dao)
      helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        lua_ssl_trusted_certificate = "../spec/fixtures/kong_spec.crt",
        stream_listen = "0.0.0.0:9100",
        db_update_frequency = 0.1,
      })
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    describe("#healthchecks (#cluster)", function()

      -- second node ports are Kong test ports + 10
      local proxy_port_1 = 9000
      local admin_port_1 = 9001
      local proxy_port_2 = 9010
      local admin_port_2 = 9011

      lazy_setup(function()
        -- start a second Kong instance
        helpers.start_kong({
          database   = strategy,
          admin_listen = "127.0.0.1:" .. admin_port_2,
          proxy_listen = "127.0.0.1:" .. proxy_port_2,
          stream_listen = "off",
          prefix = "servroot2",
          log_level = "debug",
          db_update_frequency = 0.1,
        })
      end)

      lazy_teardown(function()
        helpers.stop_kong("servroot2", true, true)
      end)

      for mode, localhost in pairs(localhosts) do

        describe("#" .. mode, function()

          it("does not perform health checks when disabled (#3304)", function()

            local old_rv = get_router_version(admin_port_2)

            local upstream_name = add_upstream()
            local port = add_target(upstream_name, localhost)
            local api_host = add_api(upstream_name)

            wait_for_router_update(old_rv, localhost, proxy_port_2, admin_port_2)

            -- server responds, then fails, then responds again
            local server = http_server(localhost, port, { 20, 20, 20 })

            local seq = {
              { port = proxy_port_2, oks = 10, fails = 0, last_status = 200 },
              { port = proxy_port_1, oks = 10, fails = 0, last_status = 200 },
              { port = proxy_port_2, oks = 0, fails = 10, last_status = 500 },
              { port = proxy_port_1, oks = 0, fails = 10, last_status = 500 },
              { port = proxy_port_2, oks = 10, fails = 0, last_status = 200 },
              { port = proxy_port_1, oks = 10, fails = 0, last_status = 200 },
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

          end)

          it("propagates posted health info #flaky", function()

            local old_rv = get_router_version(admin_port_2)

            local upstream_name = add_upstream({
              healthchecks = healthchecks_config {}
            })
            local port = add_target(upstream_name, localhost)

            wait_for_router_update(old_rv, localhost, proxy_port_2, admin_port_2)

            local health1 = get_upstream_health(upstream_name, admin_port_1)
            local health2 = get_upstream_health(upstream_name, admin_port_2)

            assert.same("HEALTHY", health1.data[1].health)
            assert.same("HEALTHY", health2.data[1].health)

            post_target_endpoint(upstream_name, localhost, port, "unhealthy")

            poll_wait_health(upstream_name, localhost, port, "UNHEALTHY", admin_port_1)
            poll_wait_health(upstream_name, localhost, port, "UNHEALTHY", admin_port_2)

          end)

        end)
      end
    end)

    for mode, localhost in pairs(localhosts) do

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

          it("can have their config partially updated", function()
            local upstream_name = add_upstream()

            patch_upstream(upstream_name, {
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

            local updated = {
              active = {
                type = "http",
                concurrency = 10,
                healthy = {
                  http_statuses = { 200, 302 },
                  interval = 0,
                  successes = 1
                },
                http_path = "/status",
                https_verify_certificate = true,
                timeout = 1,
                unhealthy = {
                  http_failures = 1,
                  http_statuses = { 429, 404, 500, 501, 502, 503, 504, 505 },
                  interval = 0,
                  tcp_failures = 0,
                  timeouts = 0
                }
              },
              passive = {
                type = "http",
                healthy = {
                  http_statuses = { 200, 201, 202, 203, 204, 205, 206, 207, 208, 226,
                                    300, 301, 302, 303, 304, 305, 306, 307, 308 },
                  successes = 0
                },
                unhealthy = {
                  http_failures = 0,
                  http_statuses = { 429, 500, 503 },
                  tcp_failures = 0,
                  timeouts = 0
                }
              }
            }

            local upstream_data = get_upstream(upstream_name)
            assert.same(updated, upstream_data.healthchecks)
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
            assert.truthy(hcs < 2)
          end)

        end)

        describe("#healthchecks", function()

          it("do not count Kong-generated errors as failures", function()

            -- configure healthchecks with a 1-error threshold
            local upstream_name = add_upstream({
              healthchecks = healthchecks_config {
                passive = {
                  healthy = {
                    successes = 1,
                  },
                  unhealthy = {
                    http_statuses = { 401, 500 },
                    http_failures = 1,
                    tcp_failures = 1,
                    timeouts = 1,
                  },
                }
              }
            })
            local port1 = add_target(upstream_name, localhost)
            local port2 = add_target(upstream_name, localhost)
            local api_host, api_name = add_api(upstream_name)

            -- add a plugin
            local plugin_id = add_plugin(api_name, {
              name = "key-auth"
            })

            -- run request: fails with 401, but doesn't hit the 1-error threshold
            local oks, fails, last_status = client_requests(1, api_host)
            assert.same(0, oks)
            assert.same(1, fails)
            assert.same(401, last_status)

            -- delete the plugin
            delete_plugin(api_name, plugin_id)

            -- start servers, they are unaffected by the failure above
            local server1 = http_server(localhost, port1, { SLOTS })
            local server2 = http_server(localhost, port2, { SLOTS })

            oks, fails = client_requests(SLOTS * 2, api_host)
            assert.same(SLOTS * 2, oks)
            assert.same(0, fails)

            -- collect server results
            local _, ok1, fail1 = server1:done()
            local _, ok2, fail2 = server2:done()

            -- both servers were fully operational
            assert.same(SLOTS, ok1)
            assert.same(SLOTS, ok2)
            assert.same(0, fail1)
            assert.same(0, fail2)

          end)

          it("#perform passive health checks", function()

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
              })
              local port1 = add_target(upstream_name, localhost)
              local port2 = add_target(upstream_name, localhost)
              local api_host = add_api(upstream_name)

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

          it("#stream and http modules do not duplicate active health checks", function()

            local port1 = gen_port()

            local server1 = http_server(localhost, port1, { 1 })

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
                    http_failures = 1,
                  },
                }
              }
            })
            add_target(upstream_name, localhost, port1)

            ngx.sleep(HEALTHCHECK_INTERVAL * 5)

            -- collect server results; hitcount
            local _, _, _, hcs1 = server1:done()

            assert(hcs1 < 8)
          end)

          it("perform active health checks -- up then down", function()

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
              })
              add_target(upstream_name, localhost, port1)
              add_target(upstream_name, localhost, port2)
              local api_host = add_api(upstream_name)

              -- Phase 1: server1 and server2 take requests
              local client_oks, client_fails = client_requests(server2_oks * 2, api_host)

              -- Phase 2: server2 goes unhealthy
              direct_request(localhost, port2, "/unhealthy")

              -- Give time for healthchecker to detect
              poll_wait_health(upstream_name, localhost, port2, "UNHEALTHY")

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

          for _, protocol in ipairs({"http", "https"}) do
            it("perform active health checks -- automatic recovery #" .. protocol, function()
              for nchecks = 1, 3 do

                local port1 = gen_port()
                local port2 = gen_port()

                -- setup target servers:
                -- server2 will only respond for part of the test,
                -- then server1 will take over.
                local server1_oks = SLOTS * 2
                local server2_oks = SLOTS
                local server1 = http_server(localhost, port1, { server1_oks }, nil, protocol)
                local server2 = http_server(localhost, port2, { server2_oks }, nil, protocol)

                -- configure healthchecks
                local upstream_name = add_upstream({
                  healthchecks = healthchecks_config {
                    active = {
                      type = protocol,
                      http_path = "/status",
                      https_verify_certificate = (protocol == "https" and localhost == "localhost"),
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
                })
                add_target(upstream_name, localhost, port1)
                add_target(upstream_name, localhost, port2)
                local api_host = add_api(upstream_name)

                -- 1) server1 and server2 take requests
                local oks, fails = client_requests(SLOTS, api_host)

                -- server2 goes unhealthy
                direct_request(localhost, port2, "/unhealthy")
                -- Wait until healthchecker detects
                poll_wait_health(upstream_name, localhost, port2, "UNHEALTHY")

                -- 2) server1 takes all requests
                do
                  local o, f = client_requests(SLOTS, api_host)
                  oks = oks + o
                  fails = fails + f
                end

                -- server2 goes healthy again
                direct_request(localhost, port2, "/healthy")
                -- Give time for healthchecker to detect
                poll_wait_health(upstream_name, localhost, port2, "HEALTHY")

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
          end

          it("perform active health checks -- can detect before any proxy traffic", function()

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
            })
            add_target(upstream_name, localhost, port1)
            add_target(upstream_name, localhost, port2)
            local api_host = add_api(upstream_name)

            -- server2 goes unhealthy before the first request
            direct_request(localhost, port2, "/unhealthy")

            -- restart Kong
            helpers.stop_kong(nil, true, true)
            helpers.start_kong({
              database   = strategy,
              nginx_conf = "spec/fixtures/custom_nginx.template",
              lua_ssl_trusted_certificate = "../spec/fixtures/kong_spec.crt",
              db_update_frequency = 0.1,
              stream_listen = "0.0.0.0:9100",
            })

            -- Give time for healthchecker to detect
            poll_wait_health(upstream_name, localhost, port2, "UNHEALTHY")

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

          it("perform passive health checks -- manual recovery", function()

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
              })
              local port1 = add_target(upstream_name, localhost)
              local port2 = add_target(upstream_name, localhost)
              local api_host = add_api(upstream_name)

              -- setup target servers:
              -- server2 will only respond for part of the test,
              -- then server1 will take over.
              local server1_oks = SLOTS * 2 - nfails
              local server2_oks = SLOTS
              local server1 = http_server(localhost, port1, {
                server1_oks
              })
              local server2 = http_server(localhost, port2, {
                server2_oks / 2,
                nfails,
                server2_oks / 2
              })

              -- 1) server1 and server2 take requests
              local oks, fails = client_requests(SLOTS, api_host)

              -- 2) server1 takes all requests once server2 produces
              -- `nfails` failures (even though server2 will be ready
              -- to respond 200 again after `nfails`)
              do
                local o, f = client_requests(SLOTS, api_host)
                oks = oks + o
                fails = fails + f
              end

              -- manually bring it back using the endpoint
              post_target_endpoint(upstream_name, localhost, port2, "healthy")

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
              assert.are.equal(server1_oks, ok1)
              assert.are.equal(server2_oks, ok2)
              assert.are.equal(0, fail1)
              assert.are.equal(nfails, fail2)

              assert.are.equal(SLOTS * 3 - nfails, oks)
              assert.are.equal(nfails, fails)
            end
          end)

          it("perform passive health checks -- manual shutdown", function()

            -- configure healthchecks
            local upstream_name = add_upstream({
              healthchecks = healthchecks_config {
                passive = {
                  unhealthy = {
                    http_failures = 1,
                  }
                }
              }
            })
            local port1 = add_target(upstream_name, localhost)
            local port2 = add_target(upstream_name, localhost)
            local api_host = add_api(upstream_name)

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
            post_target_endpoint(upstream_name, localhost, port2, "unhealthy")

            -- 2) server1 takes all requests
            do
              local o, f = client_requests(SLOTS, api_host)
              oks = oks + o
              fails = fails + f
            end

            -- manually bring it back using the endpoint
            post_target_endpoint(upstream_name, localhost, port2, "healthy")

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

          it("perform passive health checks -- connection #timeouts", function()

            -- configure healthchecks
            local upstream_name = add_upstream({
              healthchecks = healthchecks_config {
                passive = {
                  unhealthy = {
                    timeouts = 1,
                  }
                }
              }
            })
            local port1 = add_target(upstream_name, localhost)
            local port2 = add_target(upstream_name, localhost)
            local api_host = add_api(upstream_name, 50, 50)

            -- setup target servers:
            -- server2 will only respond for half of the test
            -- then will timeout on the following request.
            -- Then server1 will take over.
            local server1_oks = SLOTS * 1.5
            local server2_oks = SLOTS / 2
            local server1 = http_server(localhost, port1, {
              server1_oks
            })
            local server2 = http_server(localhost, port2, {
              server2_oks,
              TIMEOUT,
            })

            -- 1) server1 and server2 take requests
            local oks, fails = client_requests(SLOTS, api_host)

            -- 2) server1 takes all requests once server2 produces
            -- `nfails` failures (even though server2 will be ready
            -- to respond 200 again after `nfails`)
            do
              local o, f = client_requests(SLOTS, api_host)
              oks = oks + o
              fails = fails + f
            end

            -- collect server results; hitcount
            local _, ok1, fail1 = server1:done()
            local _, ok2, fail2 = server2:done()

            -- verify
            assert.are.equal(server1_oks, ok1)
            assert.are.equal(server2_oks, ok2)
            assert.are.equal(0, fail1)
            assert.are.equal(1, fail2)

            assert.are.equal(SLOTS * 2, oks)
            assert.are.equal(0, fails)
          end)

          local stream_it = (mode == "ipv6") and pending or it
          stream_it("perform passive health checks -- #stream connection failure", function()

            -- configure healthchecks
            local upstream_name = add_upstream({
              healthchecks = healthchecks_config {
                passive = {
                  unhealthy = {
                    tcp_failures = 1,
                  }
                }
              }
            })
            local port1 = add_target(upstream_name, localhost)
            local port2 = add_target(upstream_name, localhost)
            local _, service_name, route_id = add_api(upstream_name, 50, 50, nil, nil, "tcp")
            finally(function()
              delete_api(service_name, route_id)
            end)

            -- setup target servers:
            -- server2 will only respond for half of the test and will shutdown.
            -- Then server1 will take over.
            local server1_oks = SLOTS * 1.5
            local server2_oks = SLOTS / 2
            local server1 = helpers.tcp_server(port1, {
              requests = server1_oks,
              prefix = "1 ",
            })
            local server2 = helpers.tcp_server(port2, {
              requests = server2_oks,
              prefix = "2 ",
            })
            ngx.sleep(1)

            -- server1 and server2 take requests
            -- server1 takes all requests once server2 fails
            local ok1 = 0
            local ok2 = 0
            local fails = 0
            for _ = 1, SLOTS * 2 do
              local sock = ngx.socket.tcp()
              assert(sock:connect(localhost, 9100))
              assert(sock:send("hello\n"))
              local response, err = sock:receive()
              if err then
                fails = fails + 1
                print(err)
              elseif response:match("^1 ") then
                ok1 = ok1 + 1
              elseif response:match("^2 ") then
                ok2 = ok2 + 1
              end
            end

            -- finish up TCP server threads
            server1:join()
            server2:join()

            -- verify
            assert.are.equal(server1_oks, ok1)
            assert.are.equal(server2_oks, ok2)
            assert.are.equal(0, fails)
          end)

          it("perform passive health checks -- send #timeouts", function()

            -- configure healthchecks
            local upstream_name = add_upstream({
              healthchecks = healthchecks_config {
                passive = {
                  unhealthy = {
                    http_failures = 0,
                    timeouts = 1,
                    tcp_failures = 0,
                  }
                }
              }
            })
            local port1 = add_target(upstream_name, localhost)
            local api_host, api_name = add_api(upstream_name, 10, nil, nil, 0)

            local server1 = http_server(localhost, port1, {
              TIMEOUT,
            })

            local _, _, last_status = client_requests(1, api_host)
            assert.same(504, last_status)

            local _, oks1, fails1 = server1:done()
            assert.same(1, oks1)
            assert.same(0, fails1)

            patch_api(api_name, nil, 60000)

            local port2 = add_target(upstream_name, localhost)
            local server2 = http_server(localhost, port2, {
              10,
            })

            _, _, last_status = client_requests(10, api_host)
            assert.same(200, last_status)

            local _, oks2, fails2 = server2:done()
            assert.same(10, oks2)
            assert.same(0, fails2)

          end)

        end)

        describe("Balancing", function()

          describe("with round-robin", function()

            it("over multiple targets", function()

              local upstream_name = add_upstream()
              local port1 = add_target(upstream_name, localhost)
              local port2 = add_target(upstream_name, localhost)
              local api_host = add_api(upstream_name)

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

              local upstream_name = add_upstream()
              local port1 = add_target(upstream_name, localhost, nil, { weight = 10 })
              local port2 = add_target(upstream_name, localhost, nil, { weight = 10 })
              local api_host = add_api(upstream_name)

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
              local port3 = add_target(upstream_name, localhost, nil, { weight = 5 })

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

              local upstream_name = add_upstream()
              local port1 = add_target(upstream_name, localhost)
              local port2 = add_target(upstream_name, localhost)
              local api_host = add_api(upstream_name)

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
              })

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
            it("modifying target weight", function()
              local requests = SLOTS * 2 -- go round the balancer twice

              local upstream_name = add_upstream()
              local port1 = add_target(upstream_name, localhost)
              local port2 = add_target(upstream_name, localhost)
              local api_host = add_api(upstream_name)

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

              -- modify weight for target 2
              add_target(upstream_name, localhost, port2, {
                weight = 15,   -- shift proportions from 50/50 to 40/60
              })

              -- now go and hit the same balancer again
              -----------------------------------------

              -- setup target servers
              server1 = http_server(localhost, port1, { requests * 0.4 })
              server2 = http_server(localhost, port2, { requests * 0.6 })

              -- Go hit them with our test requests
              oks = client_requests(requests, api_host)
              assert.are.equal(requests, oks)

              -- collect server results; hitcount
              _, count1 = server1:done()
              _, count2 = server2:done()

              -- verify
              assert.are.equal(requests * 0.4, count1)
              assert.are.equal(requests * 0.6, count2)
            end)

            it("failure due to targets all 0 weight", function()
              local requests = SLOTS * 2 -- go round the balancer twice

              local upstream_name = add_upstream()

              local port1 = add_target(upstream_name, localhost)
              local port2 = add_target(upstream_name, localhost)
              local api_host = add_api(upstream_name)

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

              -- modify weight for both targets, set to 0
              add_target(upstream_name, localhost, port1, { weight = 0 })
              add_target(upstream_name, localhost, port2, { weight = 0 })

              -- now go and hit the same balancer again
              -----------------------------------------

              local _, _, status = client_requests(1, api_host)
              assert.same(503, status)
            end)

          end)

          describe("with consistent hashing", function()

            describe("over multiple targets", function()

              it("hashing on header", function()
                local requests = SLOTS * 2 -- go round the balancer twice

                local upstream_name = add_upstream({
                  hash_on = "header",
                  hash_on_header = "hashme",
                })
                local port1 = add_target(upstream_name, localhost)
                local port2 = add_target(upstream_name, localhost)
                local api_host = add_api(upstream_name)

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

              describe("hashing on cookie", function()
                it("does not reply with Set-Cookie if cookie is already set", function()
                  local upstream_name = add_upstream({
                    hash_on = "cookie",
                    hash_on_cookie = "hashme",
                  })
                  local port = add_target(upstream_name, localhost)
                  local api_host = add_api(upstream_name)

                  -- setup target server
                  local server = http_server(localhost, port, { 1 })

                  -- send request
                  local client = helpers.proxy_client()
                  local res = client:send {
                    method = "GET",
                    path = "/",
                    headers = {
                      ["Host"] = api_host,
                      ["Cookie"] = "hashme=some-cookie-value",
                    }
                  }
                  local set_cookie = res.headers["Set-Cookie"]

                  client:close()
                  server:done()

                  -- verify
                  assert.is_nil(set_cookie)
                end)

                it("replies with Set-Cookie if cookie is not set", function()
                  local requests = SLOTS * 2 -- go round the balancer twice

                  local upstream_name = add_upstream({
                    hash_on = "cookie",
                    hash_on_cookie = "hashme",
                  })
                  local port1 = add_target(upstream_name, localhost)
                  local port2 = add_target(upstream_name, localhost)
                  local api_host = add_api(upstream_name)

                  -- setup target servers
                  local server1 = http_server(localhost, port1, { requests })
                  local server2 = http_server(localhost, port2, { requests })

                  -- initial request without the `hash_on` cookie
                  local client = helpers.proxy_client()
                  local res = client:send {
                    method = "GET",
                    path = "/",
                    headers = {
                      ["Host"] = api_host,
                      ["Cookie"] = "some-other-cooke=some-other-value",
                    }
                  }
                  local cookie = res.headers["Set-Cookie"]:match("hashme%=(.*)%;")

                  client:close()

                  -- subsequent requests add the cookie that was set by the first response
                  local oks = 1 + client_requests(requests - 1, {
                    ["Host"] = api_host,
                    ["Cookie"] = "hashme=" .. cookie,
                  })
                  assert.are.equal(requests, oks)

                  -- collect server results; hitcount
                  -- one should get all the hits, the other 0
                  local _, count1 = server1:done()
                  local _, count2 = server2:done()

                  -- verify
                  assert(count1 == 0 or count1 == requests,
                         "counts should either get 0 or ALL hits, but got " .. count1 .. " of " .. requests)
                  assert(count2 == 0 or count2 == requests,
                         "counts should either get 0 or ALL hits, but got " .. count2 .. " of " .. requests)
                  assert(count1 + count2 == requests)
                end)

              end)

            end)

          end)

          describe("with no targets", function()

            it("failure due to no targets", function()

              local upstream_name = add_upstream()
              local api_host = add_api(upstream_name)

              -- Go hit it with a request
              local _, _, status = client_requests(1, api_host)
              assert.same(503, status)

            end)

          end)
        end)
      end)
    end -- for 'localhost'
  end)
end -- for each_strategy

