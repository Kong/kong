local cjson   = require "cjson"
local helpers = require "spec.helpers"

local https_server = helpers.https_server


local test_port1 = helpers.get_available_port()
local test_port2 = helpers.get_available_port()


-- create two servers, one double the delay of the other
local server1 = https_server.new(test_port1, "127.0.0.1", "http", false, nil, 100)
local server2 = https_server.new(test_port2, "127.0.0.1", "http", false, nil, 1000)

for _, strategy in helpers.each_strategy() do
  describe("Balancer: ewma [#" .. strategy .. "]", function()
    local upstream1_id

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "upstreams",
        "targets",
      })

      assert(bp.routes:insert({
        hosts      = { "ewma1.test" },
        protocols  = { "http" },
        service    = bp.services:insert({
          protocol = "http",
          host     = "ewmaupstream",
        })
      }))

      local upstream1 = assert(bp.upstreams:insert({
        name = "ewmaupstream",
        algorithm = "ewma",
      }))
      upstream1_id = upstream1.id

      assert(bp.targets:insert({
        upstream = upstream1,
        target = "127.0.0.1:" .. test_port1,
        weight = 100,
      }))

      assert(bp.targets:insert({
        upstream = upstream1,
        target = "127.0.0.1:" .. test_port2,
        weight = 100,
      }))

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    it("balances by ewma", function()
      server1:start()
      server2:start()
      local thread_max = 100 -- maximum number of threads to use
      local threads = {}

      local handler = function()
        local client = helpers.proxy_client()
        local res = assert(client:send({
          method = "GET",
          path = "/ewma",
          headers = {
            ["Host"] = "ewma1.test"
          },
        }))
        assert(res.status == 200)
        client:close()
      end

      -- start the threads
      for i = 1, 6 do
        threads[#threads+1] = ngx.thread.spawn(handler)
      end

      -- avoid to concurrency request
      ngx.update_time()
      ngx.sleep(2)

      for i = 7, thread_max do
        threads[#threads+1] = ngx.thread.spawn(handler)
      end

      -- wait while we're executing
      local finish_at = ngx.now() + 1.5
      repeat
        ngx.sleep(0.01)
      until ngx.now() >= finish_at

      -- finish up
      for i = 1, thread_max do
        ngx.thread.wait(threads[i])
      end

      local results1 = server1:shutdown()
      local results2 = server2:shutdown()
      local ratio = results1.ok/results2.ok
      ngx.log(ngx.ERR, "ratio: ", results1.ok, "/", results2.ok)
      assert(ratio > 10, "ewma balancer request error")
      assert.is_not(ratio, 0)
    end)

    if strategy ~= "off" then
      it("add and remove targets", function()
        local api_client = helpers.admin_client()

        -- create a new target
        local res = assert(api_client:post("/upstreams/" .. upstream1_id .. "/targets", {
          headers = {
            ["Content-Type"] = "application/json",
          },
          body = {
            target = "127.0.0.1:10003",
            weight = 100
          },
        }))
        api_client:close()
        assert.same(201, res.status)

        -- check if it is available
        api_client = helpers.admin_client()
        local res, err = api_client:send({
          method = "GET",
          path = "/upstreams/" .. upstream1_id .. "/targets/all",
        })
        assert.is_nil(err)

        local body = cjson.decode((res:read_body()))
        api_client:close()
        local found = false
        for _, entry in ipairs(body.data) do
          if entry.target == "127.0.0.1:10003" and entry.weight == 100 then
            found = true
            break
          end
        end
        assert.is_true(found)

        -- update the target and assert that it still exists with weight == 0
        api_client = helpers.admin_client()
        res, err = api_client:send({
          method = "PATCH",
          path = "/upstreams/" .. upstream1_id .. "/targets/127.0.0.1:10003",
          headers = {
            ["Content-Type"] = "application/json",
          },
          body = {
            weight = 0
          },
        })
        assert.is_nil(err)
        assert.same(200, res.status)
        local json = assert.response(res).has.jsonbody()
        assert.is_string(json.id)
        assert.are.equal("127.0.0.1:10003", json.target)
        assert.are.equal(0, json.weight)
        api_client:close()

        api_client = helpers.admin_client()
        local res, err = api_client:send({
          method = "GET",
          path = "/upstreams/" .. upstream1_id .. "/targets/all",
        })
        assert.is_nil(err)

        local body = cjson.decode((res:read_body()))
        api_client:close()
        local found = false
        for _, entry in ipairs(body.data) do
          if entry.target == "127.0.0.1:10003" and entry.weight == 0 then
            found = true
            break
          end
        end
        assert.is_true(found)
      end)
    end
  end)

  if strategy ~= "off" then
    describe("Balancer: add and remove a single target to a ewma upstream [#" .. strategy .. "]", function()
      local bp

      lazy_setup(function()
        bp = helpers.get_db_utils(strategy, {
          "routes",
          "services",
          "upstreams",
          "targets",
        })

        assert(helpers.start_kong({
          database   = strategy,
          nginx_conf = "spec/fixtures/custom_nginx.template",
        }))
      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      it("add and remove targets", function()
        local an_upstream = assert(bp.upstreams:insert({
          name = "anupstream",
          algorithm = "ewma",
        }))

        local api_client = helpers.admin_client()

        -- create a new target
        local res = assert(api_client:post("/upstreams/" .. an_upstream.id .. "/targets", {
          headers = {
            ["Content-Type"] = "application/json",
          },
          body = {
            target = "127.0.0.1:" .. test_port1,
            weight = 100
          },
        }))
        api_client:close()
        assert.same(201, res.status)

        -- check if it is available
        api_client = helpers.admin_client()
        local res, err = api_client:send({
          method = "GET",
          path = "/upstreams/" .. an_upstream.id .. "/targets/all",
        })
        assert.is_nil(err)

        local body = cjson.decode((res:read_body()))
        api_client:close()
        local found = false
        for _, entry in ipairs(body.data) do
          if entry.target == "127.0.0.1:" .. test_port1 and entry.weight == 100 then
            found = true
            break
          end
        end
        assert.is_true(found)

        -- delete the target and assert that it is gone
        api_client = helpers.admin_client()
        res, err = api_client:send({
          method = "DELETE",
          path = "/upstreams/" .. an_upstream.id .. "/targets/127.0.0.1:" .. test_port1,
        })
        assert.is_nil(err)
        assert.same(204, res.status)
        api_client:close()

        api_client = helpers.admin_client()
        local res, err = api_client:send({
          method = "GET",
          path = "/upstreams/" .. an_upstream.id .. "/targets/all",
        })
        assert.is_nil(err)

        local body = cjson.decode((res:read_body()))
        api_client:close()
        local found = false
        for _, entry in ipairs(body.data) do
          if entry.target == "127.0.0.1:" .. test_port1 and entry.weight == 0 then
            found = true
            break
          end
        end
        assert.is_false(found)
      end)
    end)
  end
end
