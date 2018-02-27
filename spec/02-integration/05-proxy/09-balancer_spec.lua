-- these tests only apply to the ring-balancer
-- for dns-record balancing see the `dns_spec` files

local helpers = require "spec.helpers"
local dao_helpers = require "spec.02-integration.03-dao.helpers"
local PORT = 21000
local utils = require "kong.tools.utils"
local cjson = require "cjson"

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


local TEST_LOG = false    -- extra verbose logging of test server


local function direct_request(host, port, path)
  local pok, client = pcall(helpers.http_client, host, port)
  if not pok then
    return nil, "pcall"
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
-- @param timeout Server timeout.
-- @param host Host name to use (IPv4 or IPv6 localhost).
-- @param port Port number to use.
-- @param counts Array of response counts to give,
-- odd entries are 200s, event entries are 500s
-- @param test_log (optional, default fals) Produce detailed logs
-- @return Returns the number of succesful and failure responses.
local function http_server(timeout, host, port, counts, test_log)
  local threads = require "llthreads2.ex"
  local thread = threads.new({
    function(timeout, host, port, counts, TEST_LOG)
      local function test_log(...)
        if not TEST_LOG then
          return
        end

        local t = { n = select( "#", ...), ...}
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

      local expire = socket.gettime() + timeout
      assert(server:settimeout(0.5))
      test_log("test http server on port ", port, " started")

      local healthy = true
      local n_checks = 0

      local ok_responses, fail_responses = 0, 0
      local total_reqs = 0
      for _, c in pairs(counts) do
        total_reqs = total_reqs + c
      end
      local n_reqs = 0
      local reply_200 = true
      while n_reqs < total_reqs do
        local client, err
        client, err = server:accept()
        if socket.gettime() > expire then
          server:close()
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
          local got_handshake = lines[1]:match("/handshake")
          if got_handshake then
            client:send("HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n")
            client:close()
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
            client:close()
            n_checks = n_checks + 1

          elseif lines[1]:match("/healthy") then
            healthy = true
            client:send("HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n")
            client:close()

          elseif lines[1]:match("/unhealthy") then
            healthy = false
            client:send("HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n")
            client:close()

          elseif handshake_done and not got_handshake then
            n_reqs = n_reqs + 1

            while counts[1] == 0 do
              table.remove(counts, 1)
              reply_200 = not reply_200
            end
            if not counts[1] then
              error("unexpected request")
            end
            if counts[1] > 0 then
              counts[1] = counts[1] - 1
            end

            local response
            if reply_200 then
              response = "HTTP/1.1 200 OK"
            else
              response = "HTTP/1.1 500 Internal Server Error"
            end
            local sent = client:send(response .. "\r\nConnection: close\r\n\r\n")
            client:close()
            if sent then
              if reply_200 then
                ok_responses = ok_responses + 1
              else
                fail_responses = fail_responses + 1
              end
            end

          else
            error("got a request before the handshake was complete")
          end
          test_log("test http server on port ", port, ": ", ok_responses, " oks, ",
                   fail_responses," fails handled")
        end
      end
      server:close()
      test_log("test http server on port ", port, " closed")
      return ok_responses, fail_responses, n_checks
    end
  }, timeout, host, port, counts, test_log or TEST_LOG)

  local server = thread:start()

  local expire = ngx.now() + timeout
  repeat
    local _, err = direct_request(host, port, "/handshake")
    if err then
      ngx.sleep(0.01) -- poll-wait
    end
  until (ngx.now() > expire) or not err

  return server
end


local function client_requests(n, headers)
  local oks, fails = 0, 0
  local last_status
  for _ = 1, n do
    local client = helpers.proxy_client()
    local res = client:send {
      method = "GET",
      path = "/",
      headers = headers or {
        ["Host"] = "balancer.test"
      }
    }
    if not res then
      fails = fails + 1
    elseif res.status == 200 then
      oks = oks + 1
    elseif res.status > 399 then
      fails = fails + 1
    end
    last_status = res and res.status
    client:close()
  end
  return oks, fails, last_status
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
    return nil, err
  end
  api_client:close()
  return res.status
end


local localhosts = {
  ipv4 = "127.0.0.1",
  ipv6 = "[0000:0000:0000:0000:0000:0000:0000:0001]",
  hostname = "localhost",
}


for mode, localhost in pairs(localhosts) do


dao_helpers.for_each_dao(function(kong_config)

  describe("Ring-balancer #" .. kong_config.database .. " #" .. mode, function()
    local config_db

    setup(function()
      helpers.run_migrations()
      config_db = helpers.test_conf.database
      helpers.test_conf.database = kong_config.database
      helpers.run_migrations()
    end)
    teardown(function()
      helpers.test_conf.database = config_db
      config_db = nil
    end)

    before_each(function()
      collectgarbage()
      collectgarbage()
    end)

    describe("Upstream entities", function()

      before_each(function()
        helpers.stop_kong()
        helpers.run_migrations()
        helpers.start_kong()
      end)

      after_each(function()
        helpers.stop_kong(nil, true)
      end)

      -- Regression test for a missing invalidation in 0.12rc1
      it("created via the API are functional", function()
        assert.same(201, api_send("POST", "/upstreams", {
          name = "test_upstream", slots = 10,
        }))
        assert.same(201, api_send("POST", "/upstreams/test_upstream/targets", {
          target = utils.format_host(localhost, 2112),
        }))
        assert.same(201, api_send("POST", "/apis", {
          name = "test_api",
          hosts = "test_host.com",
          upstream_url = "http://test_upstream",
        }))

        local server = http_server(10, localhost, 2112, { 1 })

        local oks, fails, last_status = client_requests(1, {
          ["Host"] = "test_host.com"
        })
        assert.same(200, last_status)
        assert.same(1, oks)
        assert.same(0, fails)

        local _, server_oks, server_fails = server:join()
        assert.same(1, server_oks)
        assert.same(0, server_fails)
      end)

      it("can be renamed without producing stale cache", function()
        -- create two upstreams, each with a target pointing to a server
        for i = 1, 2 do
          local name = "test_upstr_" .. i
          assert.same(201, api_send("POST", "/upstreams", {
            name = name, slots = 10,
            healthchecks = healthchecks_config {}
          }))
          assert.same(201, api_send("POST", "/upstreams/" .. name .. "/targets", {
            target = utils.format_host(localhost, 2000 + i),
          }))
          assert.same(201, api_send("POST", "/apis", {
            name = "test_api_" .. i,
            hosts = name .. ".com",
            upstream_url = "http://" .. name,
          }))
        end

        -- start two servers
        local server1 = http_server(10, localhost, 2001, { 1 })
        local server2 = http_server(10, localhost, 2002, { 1 })

        -- rename upstream 2
        assert.same(200, api_send("PATCH", "/upstreams/test_upstr_2", {
          name = "test_upstr_3",
        }))

        -- rename upstream 1 to upstream 2's original name
        assert.same(200, api_send("PATCH", "/upstreams/test_upstr_1", {
          name = "test_upstr_2",
        }))

        -- hit a request through upstream 1 using the new name
        local oks, fails, last_status = client_requests(1, {
          ["Host"] = "test_upstr_2.com"
        })
        assert.same(200, last_status)
        assert.same(1, oks)
        assert.same(0, fails)

        -- rename upstream 2
        assert.same(200, api_send("PATCH", "/upstreams/test_upstr_3", {
          name = "test_upstr_1",
        }))

        -- a single request to upstream 2 just to make server 2 shutdown
        client_requests(1, { ["Host"] = "test_upstr_1.com" })

        -- collect results
        local _, server1_oks, server1_fails = server1:join()
        local _, server2_oks, server2_fails = server2:join()
        assert.same({1, 0}, { server1_oks, server1_fails })
        assert.same({1, 0}, { server2_oks, server2_fails })
      end)

      it("do not leave a stale healthchecker when renamed", function()

        -- start server
        local server1 = http_server(10, localhost, 2000, { 1 })

        local healthcheck_interval = 0.1
        -- create an upstream
        assert.same(201, api_send("POST", "/upstreams", {
          name = "test_upstr", slots = 10,
          healthchecks = healthchecks_config {
            active = {
              http_path = "/status",
              healthy = {
                interval = healthcheck_interval,
                successes = 1,
              },
              unhealthy = {
                interval = healthcheck_interval,
                http_failures = 1,
              },
            }
          }
        }))
        assert.same(201, api_send("POST", "/upstreams/test_upstr/targets", {
          target = utils.format_host(localhost, 2000),
        }))
        assert.same(201, api_send("POST", "/apis", {
          name = "test_api",
          hosts = "test_upstr.com",
          upstream_url = "http://test_upstr",
        }))

        -- rename upstream
        assert.same(200, api_send("PATCH", "/upstreams/test_upstr", {
          name = "test_upstr_2",
        }))

        -- reconfigure healthchecks
        assert.same(200, api_send("PATCH", "/upstreams/test_upstr_2", {
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
        }))

        -- give time for healthchecker to (not!) run
        ngx.sleep(healthcheck_interval * 5)

        assert.same(200, api_send("PATCH", "/apis/test_api", {
          upstream_url = "http://test_upstr_2",
        }))

        -- a single request to upstream just to make server shutdown
        client_requests(1, { ["Host"] = "test_upstr.com" })

        -- collect results
        local _, server1_oks, server1_fails, hcs = server1:join()
        assert.same({1, 0}, { server1_oks, server1_fails })
        assert.truthy(hcs < 2)
      end)

    end)

    describe("#healthchecks", function()
      local upstream

      local slots = 20

      before_each(function()
        helpers.run_migrations()
        helpers.dao.apis:insert {
          name = "balancer.test",
          hosts = { "balancer.test" },
          upstream_url = "http://service.xyz.v1/path",
        }
        upstream = assert(helpers.dao.upstreams:insert {
          name = "service.xyz.v1",
          slots = slots,
        })
        assert(helpers.dao.targets:insert {
          target = utils.format_host(localhost, PORT),
          weight = 10,
          upstream_id = upstream.id,
        })
        assert(helpers.dao.targets:insert {
          target = utils.format_host(localhost, PORT + 1),
          weight = 10,
          upstream_id = upstream.id,
        })
        helpers.start_kong()
      end)

      after_each(function()
        helpers.stop_kong(nil, true)
      end)

      it("do not count Kong-generated errors as failures", function()

        -- configure healthchecks with a 1-error threshold
        local api_client = helpers.admin_client()
        assert(api_client:send {
          method = "PATCH",
          path = "/upstreams/" .. upstream.name,
          headers = {
            ["Content-Type"] = "application/json",
          },
          body = {
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
          },
        })
        api_client:close()

        -- add a plugin
        api_client = helpers.admin_client()
        local res = assert(api_client:send {
          method = "POST",
          path = "/apis/balancer.test/plugins/",
          headers = {
            ["Content-Type"] = "application/json",
          },
          body = {
            name = "key-auth",
          },
        })
        local plugin_id = cjson.decode((res:read_body())).id
        assert.string(plugin_id)
        api_client:close()

        -- run request: fails with 401, but doesn't hit the 1-error threshold
        local oks, fails, last_status = client_requests(1)
        assert.same(0, oks)
        assert.same(1, fails)
        assert.same(401, last_status)

        -- delete the plugin
        api_client = helpers.admin_client()
        assert(api_client:send {
          method = "DELETE",
          path = "/apis/balancer.test/plugins/" .. plugin_id,
          headers = {
            ["Content-Type"] = "application/json",
          },
          body = {},
        })
        api_client:close()

        -- start servers, they are unaffected by the failure above
        local timeout = 10
        local server1 = http_server(timeout, localhost, PORT,     { upstream.slots })
        local server2 = http_server(timeout, localhost, PORT + 1, { upstream.slots })

        oks, fails = client_requests(upstream.slots * 2)
        assert.same(upstream.slots * 2, oks)
        assert.same(0, fails)

        -- collect server results
        local _, ok1, fail1 = server1:join()
        local _, ok2, fail2 = server2:join()

        -- both servers were fully operational
        assert.same(upstream.slots, ok1)
        assert.same(upstream.slots, ok2)
        assert.same(0, fail1)
        assert.same(0, fail2)

      end)

      it("perform passive health checks", function()

        for nfails = 1, slots do

          -- configure healthchecks
          local api_client = helpers.admin_client()
          assert(api_client:send {
            method = "PATCH",
            path = "/upstreams/" .. upstream.name,
            headers = {
              ["Content-Type"] = "application/json",
            },
            body = {
              healthchecks = healthchecks_config {
                passive = {
                  unhealthy = {
                    http_failures = nfails,
                  }
                }
              }
            },
          })
          api_client:close()

          local timeout = 10
          local requests = upstream.slots * 2 -- go round the balancer twice

          -- setup target servers:
          -- server2 will only respond for part of the test,
          -- then server1 will take over.
          local server2_oks = math.floor(requests / 4)
          local server1 = http_server(timeout, localhost, PORT, {
            requests - server2_oks - nfails
          })
          local server2 = http_server(timeout, localhost, PORT + 1, {
            server2_oks,
            nfails
          })

          -- Go hit them with our test requests
          local client_oks, client_fails = client_requests(requests)

          -- collect server results; hitcount
          local _, ok1, fail1 = server1:join()
          local _, ok2, fail2 = server2:join()

          -- verify
          assert.are.equal(requests - server2_oks - nfails, ok1)
          assert.are.equal(server2_oks, ok2)
          assert.are.equal(0, fail1)
          assert.are.equal(nfails, fail2)

          assert.are.equal(requests - nfails, client_oks)
          assert.are.equal(nfails, client_fails)
        end
      end)

      it("perform active health checks -- up then down", function()

        local healthcheck_interval = 0.01

        for nfails = 1, 5 do

          local timeout = 10
          local requests = upstream.slots * 2 -- go round the balancer twice

          -- setup target servers:
          -- server2 will only respond for part of the test,
          -- then server1 will take over.
          local server2_oks = math.floor(requests / 4)
          local server1 = http_server(timeout, localhost, PORT, { requests - server2_oks })
          local server2 = http_server(timeout, localhost, PORT + 1, { server2_oks })

          -- configure healthchecks
          local api_client = helpers.admin_client()
          assert(api_client:send {
            method = "PATCH",
            path = "/upstreams/" .. upstream.name,
            headers = {
              ["Content-Type"] = "application/json",
            },
            body = {
              healthchecks = healthchecks_config {
                active = {
                  http_path = "/status",
                  healthy = {
                    interval = healthcheck_interval,
                    successes = 1,
                  },
                  unhealthy = {
                    interval = healthcheck_interval,
                    http_failures = nfails,
                  },
                }
              }
            },
          })
          api_client:close()

          -- Phase 1: server1 and server2 take requests
          local client_oks, client_fails = client_requests(server2_oks * 2)

          -- Phase 2: server2 goes unhealthy
          direct_request(localhost, PORT + 1, "/unhealthy")

          -- Give time for healthchecker to detect
          ngx.sleep((2 + nfails) * healthcheck_interval)

          -- Phase 3: server1 takes all requests
          do
            local p3oks, p3fails = client_requests(requests - (server2_oks * 2))
            client_oks = client_oks + p3oks
            client_fails = client_fails + p3fails
          end

          -- collect server results; hitcount
          local _, ok1, fail1 = server1:join()
          local _, ok2, fail2 = server2:join()

          -- verify
          assert.are.equal(requests - server2_oks, ok1)
          assert.are.equal(server2_oks, ok2)
          assert.are.equal(0, fail1)
          assert.are.equal(0, fail2)

          assert.are.equal(requests, client_oks)
          assert.are.equal(0, client_fails)
        end
      end)

      it("perform active health checks -- automatic recovery", function()

        local healthcheck_interval = 0.01

        for nchecks = 1, 5 do

          local timeout = 10

          -- setup target servers:
          -- server2 will only respond for part of the test,
          -- then server1 will take over.
          local server1_oks = upstream.slots * 2
          local server2_oks = upstream.slots
          local server1 = http_server(timeout, localhost, PORT,     { server1_oks })
          local server2 = http_server(timeout, localhost, PORT + 1, { server2_oks })

          -- configure healthchecks
          local api_client = helpers.admin_client()
          assert(api_client:send {
            method = "PATCH",
            path = "/upstreams/" .. upstream.name,
            headers = {
              ["Content-Type"] = "application/json",
            },
            body = {
              healthchecks = healthchecks_config {
                active = {
                  http_path = "/status",
                  healthy = {
                    interval = healthcheck_interval,
                    successes = nchecks,
                  },
                  unhealthy = {
                    interval = healthcheck_interval,
                    http_failures = nchecks,
                  },
                }
              }
            },
          })
          api_client:close()

          -- 1) server1 and server2 take requests
          local oks, fails = client_requests(upstream.slots)

          -- server2 goes unhealthy
          direct_request(localhost, PORT + 1, "/unhealthy")
          -- Give time for healthchecker to detect
          ngx.sleep((2 + nchecks) * healthcheck_interval)

          -- 2) server1 takes all requests
          do
            local o, f = client_requests(upstream.slots)
            oks = oks + o
            fails = fails + f
          end

          -- server2 goes healthy again
          direct_request(localhost, PORT + 1, "/healthy")
          -- Give time for healthchecker to detect
          ngx.sleep((2 + nchecks) * healthcheck_interval)

          -- 3) server1 and server2 take requests again
          do
            local o, f = client_requests(upstream.slots)
            oks = oks + o
            fails = fails + f
          end

          -- collect server results; hitcount
          local _, ok1, fail1 = server1:join()
          local _, ok2, fail2 = server2:join()

          -- verify
          assert.are.equal(upstream.slots * 2, ok1)
          assert.are.equal(upstream.slots, ok2)
          assert.are.equal(0, fail1)
          assert.are.equal(0, fail2)

          assert.are.equal(upstream.slots * 3, oks)
          assert.are.equal(0, fails)
        end
      end)

      it("perform active health checks -- can detect before any proxy traffic", function()

        local healthcheck_interval = 0.2

        local nfails = 2

        local timeout = 10
        local requests = upstream.slots * 2 -- go round the balancer twice

        -- setup target servers:
        -- server1 will respond all requests, server2 will timeout
        local server1 = http_server(timeout, localhost, PORT, { requests })
        local server2 = http_server(timeout, localhost, PORT + 1, { requests })

        -- configure healthchecks
        local api_client = helpers.admin_client()
        assert(api_client:send {
          method = "PATCH",
          path = "/upstreams/" .. upstream.name,
          headers = {
            ["Content-Type"] = "application/json",
          },
          body = {
            healthchecks = healthchecks_config {
              active = {
                http_path = "/status",
                healthy = {
                  interval = healthcheck_interval,
                  successes = 1,
                },
                unhealthy = {
                  interval = healthcheck_interval,
                  http_failures = nfails,
                  tcp_failures = nfails,
                },
              }
            }
          },
        })
        api_client:close()

        -- server2 goes unhealthy before the first request
        direct_request(localhost, PORT + 1, "/unhealthy")

        -- restart Kong
        helpers.stop_kong(nil, true, true)
        helpers.start_kong()

        -- Give time for healthchecker to detect
        ngx.sleep(0.5 + (2 + nfails) * healthcheck_interval)

        -- Phase 1: server1 takes all requests
        local client_oks, client_fails = client_requests(requests)

        helpers.stop_kong(nil, true, true)
        direct_request(localhost, PORT, "/shutdown")
        direct_request(localhost, PORT + 1, "/shutdown")

        -- collect server results; hitcount
        local _, ok1, fail1 = server1:join()
        local _, ok2, fail2 = server2:join()

        -- verify
        assert.are.equal(requests, ok1)
        assert.are.equal(0, ok2)
        assert.are.equal(0, fail1)
        assert.are.equal(0, fail2)

        assert.are.equal(requests, client_oks)
        assert.are.equal(0, client_fails)

      end)

      it("perform passive health checks -- manual recovery", function()

        for nfails = 1, 5 do
          -- configure healthchecks
          local api_client = helpers.admin_client()
          assert(api_client:send {
            method = "PATCH",
            path = "/upstreams/" .. upstream.name,
            headers = {
              ["Content-Type"] = "application/json",
            },
            body = {
              healthchecks = healthchecks_config {
                passive = {
                  unhealthy = {
                    http_failures = nfails,
                  }
                }
              }
            },
          })
          api_client:close()

          local timeout = 10

          -- setup target servers:
          -- server2 will only respond for part of the test,
          -- then server1 will take over.
          local server1_oks = upstream.slots * 2 - nfails
          local server2_oks = upstream.slots
          local server1 = http_server(timeout, localhost, PORT, {
            server1_oks
          })
          local server2 = http_server(timeout, localhost, PORT + 1, {
            server2_oks / 2,
            nfails,
            server2_oks / 2
          })

          -- 1) server1 and server2 take requests
          local oks, fails = client_requests(upstream.slots)

          -- 2) server1 takes all requests once server2 produces
          -- `nfails` failures (even though server2 will be ready
          -- to respond 200 again after `nfails`)
          do
            local o, f = client_requests(upstream.slots)
            oks = oks + o
            fails = fails + f
          end

          -- manually bring it back using the endpoint
          post_target_endpoint(upstream.name, localhost, PORT + 1, "healthy")

          -- 3) server1 and server2 take requests again
          do
            local o, f = client_requests(upstream.slots)
            oks = oks + o
            fails = fails + f
          end

          -- collect server results; hitcount
          local _, ok1, fail1 = server1:join()
          local _, ok2, fail2 = server2:join()

          -- verify
          assert.are.equal(server1_oks, ok1)
          assert.are.equal(server2_oks, ok2)
          assert.are.equal(0, fail1)
          assert.are.equal(nfails, fail2)

          assert.are.equal(upstream.slots * 3 - nfails, oks)
          assert.are.equal(nfails, fails)
        end
      end)

      it("perform passive health checks -- manual shutdown", function()

        -- configure healthchecks
        local api_client = helpers.admin_client()
        assert(api_client:send {
          method = "PATCH",
          path = "/upstreams/" .. upstream.name,
          headers = {
            ["Content-Type"] = "application/json",
          },
          body = {
            healthchecks = healthchecks_config {
              passive = {
                unhealthy = {
                  http_failures = 1,
                }
              }
            }
          },
        })
        api_client:close()

        local timeout = 10

        -- setup target servers:
        -- server2 will only respond for part of the test,
        -- then server1 will take over.
        local server1_oks = upstream.slots * 2
        local server2_oks = upstream.slots
        local server1 = http_server(timeout, localhost, PORT,     { server1_oks })
        local server2 = http_server(timeout, localhost, PORT + 1, { server2_oks })

        -- 1) server1 and server2 take requests
        local oks, fails = client_requests(upstream.slots)

        -- manually bring it down using the endpoint
        post_target_endpoint(upstream.name, localhost, PORT + 1, "unhealthy")

        -- 2) server1 takes all requests
        do
          local o, f = client_requests(upstream.slots)
          oks = oks + o
          fails = fails + f
        end

        -- manually bring it back using the endpoint
        post_target_endpoint(upstream.name, localhost, PORT + 1, "healthy")

        -- 3) server1 and server2 take requests again
        do
          local o, f = client_requests(upstream.slots)
          oks = oks + o
          fails = fails + f
        end

        -- collect server results; hitcount
        local _, ok1, fail1 = server1:join()
        local _, ok2, fail2 = server2:join()

        -- verify
        assert.are.equal(upstream.slots * 2, ok1)
        assert.are.equal(upstream.slots, ok2)
        assert.are.equal(0, fail1)
        assert.are.equal(0, fail2)

        assert.are.equal(upstream.slots * 3, oks)
        assert.are.equal(0, fails)

      end)

    end)

    describe("Balancing", function()
      local client, api_client, upstream1, upstream2, target1, target2

      before_each(function()
        helpers.run_migrations()
        -- insert an api with round-robin balancer
        assert(helpers.dao.apis:insert {
          name = "balancer.test",
          hosts = { "balancer.test" },
          upstream_url = "http://service.xyz.v1/path",
        })
        upstream1 = assert(helpers.dao.upstreams:insert {
          name = "service.xyz.v1",
          slots = 10,
        })
        target1 = assert(helpers.dao.targets:insert {
          target = utils.format_host(localhost, PORT),
          weight = 10,
          upstream_id = upstream1.id,
        })
        target2 = assert(helpers.dao.targets:insert {
          target = utils.format_host(localhost, PORT + 1),
          weight = 10,
          upstream_id = upstream1.id,
        })

        -- insert an api with consistent-hashing balancer
        assert(helpers.dao.apis:insert {
          name = "hashing.test",
          hosts = { "hashing.test" },
          upstream_url = "http://service.hashing.v1/path",
        })
        upstream2 = assert(helpers.dao.upstreams:insert {
          name = "service.hashing.v1",
          slots = 10,
          hash_on = "header",
          hash_on_header = "hashme",
        })
        assert(helpers.dao.targets:insert {
          target = utils.format_host(localhost, PORT + 2),
          weight = 10,
          upstream_id = upstream2.id,
        })
        assert(helpers.dao.targets:insert {
          target = utils.format_host(localhost, PORT + 3),
          weight = 10,
          upstream_id = upstream2.id,
        })

        -- insert additional api + upstream with no targets
        assert(helpers.dao.apis:insert {
          name = "balancer.test2",
          hosts = { "balancer.test2" },
          upstream_url = "http://service.xyz.v2/path",
        })
        assert(helpers.dao.upstreams:insert {
          name = "service.xyz.v2",
          slots = 10,
        })

        helpers.start_kong()
        client = helpers.proxy_client()
        api_client = helpers.admin_client()
      end)

      after_each(function()
        if client and api_client then
          client:close()
          api_client:close()
        end
        helpers.stop_kong(nil, true)
      end)

      it("over multiple targets", function()
        local timeout = 10
        local requests = upstream1.slots * 2 -- go round the balancer twice

        -- setup target servers
        local server1 = http_server(timeout, localhost, PORT,     { requests / 2 })
        local server2 = http_server(timeout, localhost, PORT + 1, { requests / 2 })

        -- Go hit them with our test requests
        local oks = client_requests(requests)
        assert.are.equal(requests, oks)

        -- collect server results; hitcount
        local _, count1 = server1:join()
        local _, count2 = server2:join()

        -- verify
        assert.are.equal(requests / 2, count1)
        assert.are.equal(requests / 2, count2)
      end)
      it("over multiple targets, with hashing", function()
        local timeout = 5
        local requests = upstream2.slots * 2 -- go round the balancer twice

        -- setup target servers
        local server1 = http_server(timeout, localhost, PORT + 2, { requests })
        local server2 = http_server(timeout, localhost, PORT + 3, { requests })

        -- Go hit them with our test requests
        local oks = client_requests(requests, {
          ["Host"] = "hashing.test",
          ["hashme"] = "just a value",
        })
        assert.are.equal(requests, oks)

        direct_request(localhost, PORT + 2, "/shutdown")
        direct_request(localhost, PORT + 3, "/shutdown")

        -- collect server results; hitcount
        -- one should get all the hits, the other 0, and hence a timeout
        local _, count1 = server1:join()
        local _, count2 = server2:join()

        -- verify, print a warning about the timeout error
        assert(count1 == 0 or count1 == requests, "counts should either get a timeout-error or ALL hits")
        assert(count2 == 0 or count2 == requests, "counts should either get a timeout-error or ALL hits")
        assert(count1 + count2 == requests)
      end)
      it("adding a target", function()
        local timeout = 10
        local requests = upstream1.slots * 2 -- go round the balancer twice

        -- setup target servers
        local server1 = http_server(timeout, localhost, PORT,     { requests / 2 })
        local server2 = http_server(timeout, localhost, PORT + 1, { requests / 2 })

        -- Go hit them with our test requests
        local oks = client_requests(requests)
        assert.are.equal(requests, oks)

        -- collect server results; hitcount
        local _, count1 = server1:join()
        local _, count2 = server2:join()

        -- verify
        assert.are.equal(requests / 2, count1)
        assert.are.equal(requests / 2, count2)

        -- add a new target 3
        local res = assert(api_client:send {
          method = "POST",
          path = "/upstreams/" .. upstream1.name .. "/targets",
          headers = {
            ["Content-Type"] = "application/json"
          },
          body = {
            target = utils.format_host(localhost, PORT + 2),
            weight = target1.weight / 2 ,  -- shift proportions from 50/50 to 40/40/20
          },
        })
        assert.response(res).has.status(201)

        -- now go and hit the same balancer again
        -----------------------------------------

        -- setup target servers
        local server3
        server1 = http_server(timeout, localhost, PORT,     { requests * 0.4 })
        server2 = http_server(timeout, localhost, PORT + 1, { requests * 0.4 })
        server3 = http_server(timeout, localhost, PORT + 2, { requests * 0.2 })

        -- Go hit them with our test requests
        local oks = client_requests(requests)
        assert.are.equal(requests, oks)

        -- collect server results; hitcount
        _, count1 = server1:join()
        _, count2 = server2:join()
        local _, count3 = server3:join()

        -- verify
        assert.are.equal(requests * 0.4, count1)
        assert.are.equal(requests * 0.4, count2)
        assert.are.equal(requests * 0.2, count3)
      end)
      it("removing a target", function()
        local timeout = 10
        local requests = upstream1.slots * 2 -- go round the balancer twice

        -- setup target servers
        local server1 = http_server(timeout, localhost, PORT,     { requests / 2 })
        local server2 = http_server(timeout, localhost, PORT + 1, { requests / 2 })

        -- Go hit them with our test requests
        local oks = client_requests(requests)
        assert.are.equal(requests, oks)

        -- collect server results; hitcount
        local _, count1 = server1:join()
        local _, count2 = server2:join()

        -- verify
        assert.are.equal(requests / 2, count1)
        assert.are.equal(requests / 2, count2)

        -- modify weight for target 2, set to 0
        local res = assert(api_client:send {
          method = "POST",
          path = "/upstreams/" .. upstream1.name .. "/targets",
          headers = {
            ["Content-Type"] = "application/json"
          },
          body = {
            target = target2.target,
            weight = 0,   -- disable this target
          },
        })
        assert.response(res).has.status(201)

        -- now go and hit the same balancer again
        -----------------------------------------

        -- setup target servers
        server1 = http_server(timeout, localhost, PORT, { requests })

        -- Go hit them with our test requests
        local oks = client_requests(requests)
        assert.are.equal(requests, oks)

        -- collect server results; hitcount
        _, count1 = server1:join()

        -- verify all requests hit server 1
        assert.are.equal(requests, count1)
      end)
      it("modifying target weight", function()
        local timeout = 10
        local requests = upstream1.slots * 2 -- go round the balancer twice

        -- setup target servers
        local server1 = http_server(timeout, localhost, PORT,     { requests / 2 })
        local server2 = http_server(timeout, localhost, PORT + 1, { requests / 2 })

        -- Go hit them with our test requests
        local oks = client_requests(requests)
        assert.are.equal(requests, oks)

        -- collect server results; hitcount
        local _, count1 = server1:join()
        local _, count2 = server2:join()

        -- verify
        assert.are.equal(requests / 2, count1)
        assert.are.equal(requests / 2, count2)

        -- modify weight for target 2
        local res = assert(api_client:send {
          method = "POST",
          path = "/upstreams/" .. target2.upstream_id .. "/targets",
          headers = {
            ["Content-Type"] = "application/json"
          },
          body = {
            target = target2.target,
            weight = target1.weight * 1.5,   -- shift proportions from 50/50 to 40/60
          },
        })
        assert.response(res).has.status(201)

        -- now go and hit the same balancer again
        -----------------------------------------

        -- setup target servers
        server1 = http_server(timeout, localhost, PORT,     { requests * 0.4 })
        server2 = http_server(timeout, localhost, PORT + 1, { requests * 0.6 })

        -- Go hit them with our test requests
        local oks = client_requests(requests)
        assert.are.equal(requests, oks)

        -- collect server results; hitcount
        _, count1 = server1:join()
        _, count2 = server2:join()

        -- verify
        assert.are.equal(requests * 0.4, count1)
        assert.are.equal(requests * 0.6, count2)
      end)
      it("failure due to targets all 0 weight", function()
        local timeout = 10
        local requests = upstream1.slots * 2 -- go round the balancer twice

        -- setup target servers
        local server1 = http_server(timeout, localhost, PORT,     { requests / 2 })
        local server2 = http_server(timeout, localhost, PORT + 1, { requests / 2 })

        -- Go hit them with our test requests
        local oks = client_requests(requests)
        assert.are.equal(requests, oks)

        -- collect server results; hitcount
        local _, count1 = server1:join()
        local _, count2 = server2:join()

        -- verify
        assert.are.equal(requests / 2, count1)
        assert.are.equal(requests / 2, count2)

        -- modify weight for both targets, set to 0
        local res = assert(api_client:send {
          method = "POST",
          path = "/upstreams/" .. upstream1.name .. "/targets",
          headers = {
            ["Content-Type"] = "application/json"
          },
          body = {
            target = target1.target,
            weight = 0,   -- disable this target
          },
        })
        assert.response(res).has.status(201)

        res = assert(api_client:send {
          method = "POST",
          path = "/upstreams/" .. upstream1.name .. "/targets",
          headers = {
            ["Content-Type"] = "application/json"
          },
          body = {
            target = target2.target,
            weight = 0,   -- disable this target
          },
        })
        assert.response(res).has.status(201)

        -- now go and hit the same balancer again
        -----------------------------------------

        res = assert(client:send {
          method = "GET",
          path = "/",
          headers = {
            ["Host"] = "balancer.test"
          }
        })

        assert.response(res).has.status(503)
      end)
      it("failure due to no targets", function()
        -- Go hit it with a request
        local res = assert(client:send {
          method = "GET",
          path = "/",
          headers = {
            ["Host"] = "balancer.test2"
          }
        })

        assert.response(res).has.status(503)
      end)
    end)
  end)

end) -- for 'database type'

end
