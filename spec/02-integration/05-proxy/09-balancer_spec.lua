-- these tests only apply to the ring-balancer
-- for dns-record balancing see the `dns_spec` files

local helpers = require "spec.helpers"
local dao_helpers = require "spec.02-integration.03-dao.helpers"
local PORT = 21000

local TEST_LOG = false    -- extra verbose logging of test server

-- modified http-server. Accepts (sequentially) a number of incoming
-- connections, and returns the number of succesful ones.
-- Also features a timeout setting.
local function http_server(timeout, count, port, no_timeout)
  local threads = require "llthreads2.ex"
  local thread = threads.new({
    function(timeout, count, port, no_timeout, TEST_LOG)

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

      local expire = socket.gettime() + timeout
      assert(server:settimeout(0.1))
      test_log("test http server on port ", port, " started")

      local success = 0
      while count > 0 do
        local client, err
        client, err = server:accept()
        if err == "timeout" then
          if socket.gettime() > expire then
            server:close()
            if no_timeout then
              return success
            else
              error("timeout")
            end
          end
        elseif not client then
          server:close()
          error(err)
        else
          count = count - 1

          local lines = {}
          local line, err
          while #lines < 7 do
            line, err = client:receive()
            if err then
              break
            else
              table.insert(lines, line)
            end
          end

          if err then
            client:close()
            server:close()
            error(err)
          end

          local s = client:send("HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n")
          client:close()
          if s then
            success = success + 1
          end
          test_log("test http server on port ", port, ": ", success, "/",
                   (success + count)," requests handled")
        end
      end

      server:close()
      test_log("test http server on port ", port, " closed")
      return success
    end
  }, timeout, count, port, no_timeout, TEST_LOG)

  local server = thread:start()
  ngx.sleep(0.2)  -- attempt to make sure server is started for failing CI tests
  return server
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
          target = "127.0.0.1:" .. (PORT+1),
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
          target = "127.0.0.1:" .. PORT+2,
          weight = 10,
          upstream_id = upstream2.id,
        })
        assert(helpers.dao.targets:insert {
          target = "127.0.0.1:" .. (PORT+3),
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
        for _ = 1, requests do
          local res = assert(client:send {
            method = "GET",
            path = "/",
            headers = {
              ["Host"] = "balancer.test"
            }
          })
          assert.response(res).has.status(200)
        end

        -- collect server results; hitcount
        local _, count1 = server1:join()
        local _, count2 = server2:join()

        -- verify
        assert.are.equal(requests/2, count1)
        assert.are.equal(requests/2, count2)
      end)
      it("over multiple targets, with hashing", function()
        local timeout = 5
        local requests = upstream2.slots * 2 -- go round the balancer twice

        -- setup target servers
        local server1 = http_server(timeout, requests, PORT+2, true)
        local server2 = http_server(timeout, requests, PORT+3, true)

        -- Go hit them with our test requests
        for _ = 1, requests do
          local res = assert(client:send {
            method = "GET",
            path = "/",
            headers = {
              ["Host"] = "hashing.test",
              ["hashme"] = "just a value", 
            }
          })
          assert.response(res).has.status(200)
        end

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
        for _ = 1, requests do
          local res = assert(client:send {
            method = "GET",
            path = "/",
            headers = {
              ["Host"] = "balancer.test"
            }
          })
          assert.response(res).has.status(200)
        end

        -- collect server results; hitcount
        local _, count1 = server1:join()
        local _, count2 = server2:join()

        -- verify
        assert.are.equal(requests/2, count1)
        assert.are.equal(requests/2, count2)

        -- add a new target 3
        local res = assert(api_client:send {
          method = "POST",
          path = "/upstreams/" .. upstream1.name .. "/targets",
          headers = {
            ["Content-Type"] = "application/json"
          },
          body = {
            target = "127.0.0.1:" .. (PORT+2),
            weight = target1.weight/2 ,  -- shift proportions from 50/50 to 40/40/20
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
        for _ = 1, requests do
          local res = assert(client:send {
            method = "GET",
            path = "/",
            headers = {
              ["Host"] = "balancer.test"
            }
          })
          assert.response(res).has.status(200)
        end

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
        for _ = 1, requests do
          local res = assert(client:send {
            method = "GET",
            path = "/",
            headers = {
              ["Host"] = "balancer.test"
            }
          })
          assert.response(res).has.status(200)
        end

        -- collect server results; hitcount
        local _, count1 = server1:join()
        local _, count2 = server2:join()

        -- verify
        assert.are.equal(requests/2, count1)
        assert.are.equal(requests/2, count2)

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
        for _ = 1, requests do
          local res = assert(client:send {
            method = "GET",
            path = "/",
            headers = {
              ["Host"] = "balancer.test"
            }
          })
          assert.response(res).has.status(200)
        end

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
        for _ = 1, requests do
          local res = assert(client:send {
            method = "GET",
            path = "/",
            headers = {
              ["Host"] = "balancer.test"
            }
          })
          assert.response(res).has.status(200)
        end

        -- collect server results; hitcount
        local _, count1 = server1:join()
        local _, count2 = server2:join()

        -- verify
        assert.are.equal(requests/2, count1)
        assert.are.equal(requests/2, count2)

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
        for _ = 1, requests do
          local res = assert(client:send {
            method = "GET",
            path = "/",
            headers = {
              ["Host"] = "balancer.test"
            }
          })
          assert.response(res).has.status(200)
        end

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
        for _ = 1, requests do
          local res = assert(client:send {
            method = "GET",
            path = "/",
            headers = {
              ["Host"] = "balancer.test"
            }
          })
          assert.response(res).has.status(200)
        end

        -- collect server results; hitcount
        local _, count1 = server1:join()
        local _, count2 = server2:join()

        -- verify
        assert.are.equal(requests/2, count1)
        assert.are.equal(requests/2, count2)

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
