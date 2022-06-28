-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]
local cjson = require("cjson")
local helpers = require("spec.helpers")
local inspect = require("inspect")

-- number of 200s we expect to see show up in vitals on the route
local num_iterations = 5

-- used to wait for the plugin iterator rebuild finish
local extra_iterations = 0

local function wait_until_admin_client_2_finds(total_sent,
 params)
  helpers.wait_until(function()
    local admin_client_2 = helpers.http_client("127.0.0.1",
                                               9001)
    local res_2 = admin_client_2:send(params)
    if not res_2 then
      admin_client_2:close()
    end
    assert.res_status(200, res_2)
    admin_client_2:close()
    local body = assert(res_2:read_body())
    local metrics = cjson.decode(body)
    local total_200s = 0
    local stats = metrics.stats
    --[[ we are expecting something like:
    {
      cluster = {
        ["1612466880"] = {
          ["200"] = 5
        }
      }
    } --]]
    if not stats['cluster'] then
      return false, inspect(metrics)
    end
    for _, id in pairs(stats['cluster']) do
      for _, num in pairs(id) do
        total_200s = total_200s + num
      end
    end
    return total_200s == total_sent, inspect(metrics)
  end, 30)
end

for _, strategy in helpers.each_strategy() do
  describe("proxy-cache plugin works with vitals #" ..
            strategy, function()
    local bp
    local db
    local admin_client
    local proxy_client
    local service1
    local route1

    lazy_setup(function()
      bp, db = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
        "proxy-cache-advanced",
      }, {"proxy-cache-advanced"})

      db:truncate("services")
      db:truncate("routes")
      db:truncate("plugins")
      db:truncate("vitals_codes_by_route")

      service1 = bp.services:insert(
       {
         name = "mock_upstream",
         protocol = "http",
         path = "/anything",
         host = helpers.mock_upstream_host,
         port = helpers.mock_upstream_port,
       })

      route1 = bp.routes:insert(
       {
         protocols = {"http", "https"},
         hosts = {"mock_upstream"},
         methods = {"GET"},
         service = service1,
       })

      -- start Kong instance with our services and plugins
      assert(helpers.start_kong {
        plugins = "bundled,proxy-cache-advanced",
        vitals = true,
        database = strategy,
      })

      --  start mock httpbin instance
      assert(helpers.start_kong {
        plugins = "bundled,proxy-cache-advanced",
        vitals = true,
        database = strategy,
        admin_listen = "127.0.0.1:9011",
        proxy_listen = "127.0.0.1:9010",
        proxy_listen_ssl = "127.0.0.1:9453",
        admin_listen_ssl = "127.0.0.1:9454",
        prefix = "servroot2",
        nginx_conf = "spec/fixtures/custom_nginx.template",
      })
    end)

    lazy_teardown(function()
      helpers.stop_kong("servroot2")
      helpers.stop_kong(nil, true)
    end)

    before_each(function()
      if admin_client and proxy_client then
        admin_client:close()
        proxy_client:close()
      end

      admin_client = assert(helpers.admin_client())
      proxy_client = assert(helpers.proxy_client())
    end)

    describe("/plugins for route", function()
      it("succeeds with valid configuration", function()
        local res = assert(admin_client:send{
          method = "POST",
          path = "/plugins",
          body = {
            route = {id = route1.id},
            config = {
              strategy = "memory",
              content_type = {
                "text/plain",
                "application/json",
              },
              memory = {dictionary_name = "kong"},
            },
            name = "proxy-cache-advanced",
          },
          headers = {["Content-Type"] = "application/json"},
        })
        assert.res_status(201, res)
      end)
    end)

    describe("when enabled and applied to a route",
             function()
      describe("GET the route", function()
        it("succeeds as expected", function()
          for i = 1, num_iterations do
            helpers.wait_until(function()
              return pcall(function()
                local res = assert(
                 proxy_client:send{
                   method = "GET",
                   path = "/status/200",
                   headers = {["Host"] = "mock_upstream"},
                 })
                assert.res_status(200, res)

                if not res.headers["X-Cache-Status"] and i == 1 then
                  extra_iterations = extra_iterations + 1
                  return false, "falied to to wait plugin iterator to be rebuilt"
                end

                if i == 1 then
                  assert.same("Miss",
                              res.headers["X-Cache-Status"])
                else
                  assert.same("Hit",
                              res.headers["X-Cache-Status"])
                end
              end) -- pcall
            end) -- wait_until
          end -- for loop
        end) -- it
      end)
    end)

    describe("GET /vitals/status_codes/by_route", function()
      it(
       "returns the expected number of 200s with interval seconds",
       function()
         wait_until_admin_client_2_finds(num_iterations + extra_iterations, {
           method = "GET",
           path = "/vitals/status_codes/by_route",
           query = {
             interval = "seconds",
             route_id = route1.id,
           },
         })
       end)
    end)

    describe("GET /vitals/status_codes/by_route", function()
      it(
       "returns the expected number of 200s with interval minutes",
       function()
         wait_until_admin_client_2_finds(num_iterations + extra_iterations, {
           method = "GET",
           path = "/vitals/status_codes/by_route",
           query = {
             interval = "minutes",
             route_id = route1.id,
           },
         })
       end)
    end)
  end)
end
