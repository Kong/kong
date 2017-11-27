-- these tests only apply to the ring-balancer
-- for dns-record balancing see the `dns_spec` files

local helpers = require "spec.helpers"
local dao_helpers = require "spec.02-integration.03-dao.helpers"
local PORT = 21000
local utils = require "kong.tools.utils"

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


-- Modified http-server. Accepts (sequentially) a number of incoming
-- connections and then rejects a given number of connections.
-- @param timeout Server timeout.
-- @param ok_count Number of 200 OK responses to give.
-- @param port Port number to use.
-- @param fail_count (optional, default 0) Number of 500 errors to respond.
-- @return Returns the number of succesful and failure responses.
local function http_server(timeout, ok_count, port, fail_count)
  fail_count = fail_count or 0
  local threads = require "llthreads2.ex"
  local thread = threads.new({
    function(timeout, ok_count, port, fail_count)

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
      local server = assert(socket.tcp())
      assert(server:setoption('reuseaddr', true))
      assert(server:bind("*", port))
      assert(server:listen())

      local handshake_done = false

      local expire = socket.gettime() + timeout
      assert(server:settimeout(0.5))
      test_log("test http server on port ", port, " started")

      local healthy = true

      local ok_responses, fail_responses = 0, 0
      local total_reqs = ok_count + fail_count
      local n_reqs = 0
      while n_reqs < total_reqs do
        local client, err
        client, err = server:accept()
        if err == "timeout" then
          if socket.gettime() > expire then
            server:close()
            break
          end

        elseif not client then
          server:close()
          error(err)

        else
          local lines = {}
          local line, err
          while #lines < 7 do
            line, err = client:receive()
            if err then
              break

            elseif #line == 0 then
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
            local do_ok = ok_count > 0
            local response
            if do_ok then
              ok_count = ok_count - 1
              response = "HTTP/1.1 200 OK"

            else
              response = "HTTP/1.1 500 Internal Server Error"
            end
            local sent = client:send(response .. "\r\nConnection: close\r\n\r\n")
            client:close()
            if sent then
              if do_ok then
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
      return ok_responses, fail_responses
    end
  }, timeout, ok_count, port, fail_count, TEST_LOG)

  local server = thread:start()

  local expire = ngx.now() + timeout
  repeat
    local _, err = direct_request("127.0.0.1", port, "/handshake")
    if err then
      ngx.sleep(0.01) -- poll-wait
    end
  until (ngx.now() > expire) or not err

  return server
end


local function client_requests(n, headers)
  local oks, fails = 0, 0
  for _ = 1, n do
    local client = helpers.proxy_client()
    local res = client:send {
      method = "GET",
      path = "/",
      headers = headers or {
        ["Host"] = "balancer.test"
      }
    }
    if res.status == 200 then
      oks = oks + 1
    elseif res.status == 500 then
      fails = fails + 1
    end
    client:close()
  end
  return oks, fails
end


dao_helpers.for_each_dao(function(kong_config)

  describe("Ring-balancer #" .. kong_config.database, function()
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

    describe("#healthchecks", function()
      local upstream

      local slots = 20

      before_each(function()
        helpers.run_migrations()
        assert(helpers.dao.apis:insert {
          name = "balancer.test",
          hosts = { "balancer.test" },
          upstream_url = "http://service.xyz.v1/path",
        })
        upstream = assert(helpers.dao.upstreams:insert {
          name = "service.xyz.v1",
          slots = slots,
        })
        assert(helpers.dao.targets:insert {
          target = "127.0.0.1:" .. PORT,
          weight = 10,
          upstream_id = upstream.id,
        })
        assert(helpers.dao.targets:insert {
          target = "127.0.0.1:" .. (PORT + 1),
          weight = 10,
          upstream_id = upstream.id,
        })
        helpers.start_kong()
      end)

      after_each(function()
        helpers.stop_kong(nil, true)
      end)

      it("perform passive health checks", function()

        for fails = 1, slots do

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
                    http_failures = fails,
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
          local server1 = http_server(timeout, requests - server2_oks - fails, PORT)
          local server2 = http_server(timeout, server2_oks, PORT+1, fails)

          -- Go hit them with our test requests
          local client_oks, client_fails = client_requests(requests)

          -- collect server results; hitcount
          local _, ok1, fail1 = server1:join()
          local _, ok2, fail2 = server2:join()

          -- verify
          assert.are.equal(requests - server2_oks - fails, ok1)
          assert.are.equal(server2_oks, ok2)
          assert.are.equal(0, fail1)
          assert.are.equal(fails, fail2)

          assert.are.equal(requests - fails, client_oks)
          assert.are.equal(fails, client_fails)
        end
      end)

      it("perform active health checks -- up then down", function()

        local healthcheck_interval = 0.01

        for fails = 1, 5 do

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
                    http_failures = fails,
                  },
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
          local server1 = http_server(timeout, requests - server2_oks, PORT)
          local server2 = http_server(timeout, server2_oks, PORT+1)

          -- Phase 1: server1 and server2 take requests
          local client_oks, client_fails = client_requests(server2_oks * 2)

          -- Phase 2: server2 goes unhealthy
          direct_request("127.0.0.1", PORT + 1, "/unhealthy")

          -- Give time for healthchecker to detect
          ngx.sleep((2 + fails) * healthcheck_interval)

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

          local timeout = 10

          -- setup target servers:
          -- server2 will only respond for part of the test,
          -- then server1 will take over.
          local server1_oks = upstream.slots * 2
          local server2_oks = upstream.slots
          local server1 = http_server(timeout, server1_oks, PORT)
          local server2 = http_server(timeout, server2_oks, PORT+1)

          -- 1) server1 and server2 take requests
          local oks, fails = client_requests(upstream.slots)

          -- server2 goes unhealthy
          direct_request("127.0.0.1", PORT + 1, "/unhealthy")
          -- Give time for healthchecker to detect
          ngx.sleep((2 + nchecks) * healthcheck_interval)

          -- 2) server1 takes all requests
          do
            local o, f = client_requests(upstream.slots)
            oks = oks + o
            fails = fails + f
          end

          -- server2 goes healthy again
          direct_request("127.0.0.1", PORT + 1, "/healthy")
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
          target = "127.0.0.1:" .. PORT,
          weight = 10,
          upstream_id = upstream1.id,
        })
        target2 = assert(helpers.dao.targets:insert {
          target = "127.0.0.1:" .. (PORT + 1),
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
          target = "127.0.0.1:" .. PORT + 2,
          weight = 10,
          upstream_id = upstream2.id,
        })
        assert(helpers.dao.targets:insert {
          target = "127.0.0.1:" .. (PORT + 3),
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
        local server1 = http_server(timeout, requests/2, PORT)
        local server2 = http_server(timeout, requests/2, PORT+1)

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
        local server1 = http_server(timeout, requests, PORT+2, 0, true)
        local server2 = http_server(timeout, requests, PORT+3, 0, true)

        -- Go hit them with our test requests
        local oks = client_requests(requests, {
          ["Host"] = "hashing.test",
          ["hashme"] = "just a value",
        })
        assert.are.equal(requests, oks)

        direct_request("127.0.0.1", PORT + 2, "/shutdown")
        direct_request("127.0.0.1", PORT + 3, "/shutdown")

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
        local server1 = http_server(timeout, requests/2, PORT)
        local server2 = http_server(timeout, requests/2, PORT+1)

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
            target = "127.0.0.1:" .. (PORT + 2),
            weight = target1.weight / 2 ,  -- shift proportions from 50/50 to 40/40/20
          },
        })
        assert.response(res).has.status(201)

        -- now go and hit the same balancer again
        -----------------------------------------

        -- setup target servers
        server1 = http_server(timeout, requests * 0.4, PORT)
        server2 = http_server(timeout, requests * 0.4, PORT+1)
        local server3 = http_server(timeout, requests * 0.2, PORT+2)

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
        local server1 = http_server(timeout, requests/2, PORT)
        local server2 = http_server(timeout, requests/2, PORT+1)

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
        server1 = http_server(timeout, requests, PORT)

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
        local server1 = http_server(timeout, requests/2, PORT)
        local server2 = http_server(timeout, requests/2, PORT+1)

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
        server1 = http_server(timeout, requests * 0.4, PORT)
        server2 = http_server(timeout, requests * 0.6, PORT+1)

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
        local server1 = http_server(timeout, requests/2, PORT)
        local server2 = http_server(timeout, requests/2, PORT+1)

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
