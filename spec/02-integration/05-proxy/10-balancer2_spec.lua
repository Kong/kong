local helpers = require "spec.helpers"

-- create two servers, one double the delay of the other
local fixtures = {
  http_mock = {
    lambda_plugin = [[

      server {
          server_name mock_aws_lambda;
          listen 10001;

          location ~ "/leastconnections" {
              content_by_lua_block {
                local delay = 100
                ngx.sleep(delay/1000)
                ngx.status = 200
                ngx.say(delay)
                ngx.exit(0)
              }
          }
      }

      server {
          server_name mock_aws_lambda;
          listen 10002;

          location ~ "/leastconnections" {
              content_by_lua_block {
                local delay = 200
                ngx.sleep(delay/1000)
                ngx.status = 200
                ngx.say(delay)
                ngx.exit(0)
              }
          }
      }

  ]]
  },
}


for _, strategy in helpers.each_strategy() do
  describe("Balancer: least-connections [#" .. strategy .. "]", function()
    local proxy_client
    local admin_client

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "upstreams",
        "targets",
      })

      local route1 = assert(bp.routes:insert({
        hosts      = { "least1.com" },
        protocols  = { "http" },
        service    = bp.services:insert({
          protocol = "http",
          host     = "lcupstream",
        })
      }))

      local upstream1 = assert(bp.upstreams:insert({
        name = "lcupstream",
        algorithm = "least",
      }))

      local target1 = assert(bp.targets:insert({
        upstream = upstream1,
        target = "127.0.0.1:10001",
        weight = 100,
      }))

      local target2 = assert(bp.targets:insert({
        upstream = upstream1,
        target = "127.0.0.1:10002",
        weight = 100,
      }))

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }, nil, nil, fixtures))
    end)

    before_each(function()
      proxy_client = helpers.proxy_client()
      admin_client = helpers.admin_client()
    end)

    after_each(function ()
      proxy_client:close()
      admin_client:close()
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    it("balances by least-connections", function()
      local thread_max = 100 -- maximum number of threads to use
      local done = false
      local results = {}
      local threads = {}

      local handler = function()
        while not done do
          local client = helpers.proxy_client()
          local res = assert(client:send({
            method = "GET",
            path = "/leastconnections",
            headers = {
              ["Host"] = "least1.com"
            },
          }))
          assert(res.status == 200)
          local body = tonumber(assert(res:read_body()))
          results[body] = (results[body] or 0) + 1
          client:close()
        end
      end

      -- start the threads
      for i = 1, thread_max do
        threads[#threads+1] = ngx.thread.spawn(handler)
      end

      -- wait while we're executing
      local finish_at = ngx.now() + 5
      repeat
        ngx.sleep(0.1)
      until ngx.now() >= finish_at

      -- finish up
      done = true
      for i = 1, thread_max do
        ngx.thread.wait(threads[i])
      end

      --assert.equal(results,false)
      local ratio = results[100]/results[200]
      assert.near(2, ratio, 0.4)
    end)
  end)
end
