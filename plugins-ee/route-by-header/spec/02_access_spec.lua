-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local http_mock = require "spec.helpers.http_mock"

local PORT1, PORT2 = helpers.get_available_port(), helpers.get_available_port()

local strategies = helpers.all_strategies ~= nil and helpers.all_strategies or helpers.each_strategy

for _, strategy in strategies() do
  describe("Plugin: route-by-header (access) [#" .. strategy .. "]", function()
    local proxy_client, admin_client, plugin2
    local db_strategy = strategy ~= "off" and strategy or nil
    local mock1, mock2

    setup(function()
      mock1 = http_mock.new(PORT1)
      mock1:start()
      mock2 = http_mock.new(PORT2, nil, {
        prefix = "servroot_mock2",
      })
      mock2:start()
      local bp = helpers.get_db_utils(db_strategy, nil, {
        "route-by-header",
      })

      local upstream_foo = bp.upstreams:insert({
        name = "foo.domain.test"
      })

      bp.targets:insert({
        upstream = { id = upstream_foo.id },
        target = "127.0.0.1:" .. PORT1
      })

      local upstream_bar = bp.upstreams:insert({
        name = "bar.domain.test"
      })

      bp.targets:insert({
        upstream = { id = upstream_bar.id },
        target = "127.0.0.1:" .. PORT2
      })

      local service1 = bp.services:insert {
        name = "foo_upstream",
      }

      local route1 = bp.routes:insert({
        hosts = { "routebyheader1.test" },
        preserve_host = false,
        service = service1
      })

      bp.plugins:insert {
        name     = "route-by-header",
        route    = { id = route1.id },
        config = {}
      }

      local service2 = bp.services:insert {
        name = "bar_upstream",
        host = "nowhere.example.test",
        protocol= "http"
      }

      local route2 = bp.routes:insert({
        protocols = { "http" },
        hosts = { "routebyheader2.test" },
        service   = service2,
      })

      plugin2 = bp.plugins:insert {
        name     = "route-by-header",
        route    = { id = route2.id },
        config = {
          rules= {
            {
              condition = {
                header1 =  "value1",
                header2 =  "value2",
              },
              upstream_name = "bar.domain.test",
            },
            {
              condition = {
                header3 = "value3"
              },
              upstream_name = "foo.domain.test",
            }
          }
        }
      }

      assert(helpers.start_kong({
        nginx_conf = "spec/fixtures/custom_nginx.template",
        database = db_strategy,
        plugins = "bundled,route-by-header",
      }))

      proxy_client = helpers.proxy_client()
      admin_client = helpers.admin_client()
    end)

    teardown(function()
      mock1:stop()
      mock2:stop()
      if proxy_client then
        proxy_client:close()
      end
      if admin_client then
        admin_client:close()
      end
      helpers.stop_kong(nil, true)
    end)

    it("GET requests should route to default upstram server", function()
      local res = assert(proxy_client:send{
        method = "GET",
        headers = {
          Host = "routebyheader1.test"
        }
      })
      assert.res_status(200, res)
    end)
    it("GET requests should route to nowhere in case of no match", function()
      local res = assert(proxy_client:send{
        method = "GET",
        headers = {
          Host = "routebyheader2.test"
        }
      })
      assert.res_status(503, res)
    end)
    it("GET requests should route to bar server", function()
      local res = assert(proxy_client:send{
        method = "GET",
        headers = {
          Host = "routebyheader2.test",
          header1 =  "value1",
          header2 =  "value2"
        }
      })
      assert.res_status(200, res)
      mock2.eventually:has_one_without_error()
    end)
    it("GET requests should route to foo server", function()
      local res = assert(proxy_client:send{
        method = "GET",
        headers = {
          Host = "routebyheader2.test",
          header3 =  "value3",
        }
      })
      assert.res_status(200, res)
      mock1.eventually:has_one_without_error()
    end)
    it("GET requests should route to the matched, bar server", function()
      local res = assert(proxy_client:send{
        method = "GET",
        headers = {
          Host = "routebyheader2.test",
          header1 =  "value1",
          header2 =  "value2",
          header3 =  "value3",
        }
      })
      assert.res_status(200, res)
      mock2.eventually:has_one_without_error()
    end)
    it("GET requests should route to the matched, foo server after PATCH", function()
      local res = assert(proxy_client:send{
        method = "GET",
        headers = {
          Host = "routebyheader2.test",
          header1 =  "value1",
          header2 =  "value2",
          header3 =  "value3",
        }
      })
      assert.res_status(200, res)
      mock2.eventually:has_one_without_error()

      local res = assert(admin_client:send{
        method = "PATCH",
        path = "/plugins/" .. plugin2.id,
        headers = {
          ["Content-Type"] = "application/json"
        },
        body = {
          config = {
            rules= {
              {
                condition = {
                  header1 =  "value1",
                  header2 =  "value2",
                },
                upstream_name = "foo.domain.test",
              }
            }
          }
        }
      })
      assert.res_status(200, res)

      helpers.wait_for_all_config_update({
        disable_ipv6 = true,
      })

      local res = assert(proxy_client:send{
        method = "GET",
        headers = {
          Host = "routebyheader2.test",
          header1 =  "value1",
          header2 =  "value2"
        }
      })
      assert.res_status(200, res)
      mock1.eventually:has_one_without_error()
    end)
  end)
end
