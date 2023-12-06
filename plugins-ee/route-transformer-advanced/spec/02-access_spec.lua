-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local plugin_name = "route-transformer-advanced"
local helpers = require "spec.helpers"

local strategies = helpers.all_strategies ~= nil and helpers.all_strategies or helpers.each_strategy

for _, strategy in strategies() do
  describe(plugin_name .. " [#" .. strategy .. "]", function()
    local client
    local db_strategy = strategy ~= "off" and strategy or nil

    lazy_setup(function()
      local bp = helpers.get_db_utils(db_strategy, {
        "routes",
        "services",
        "plugins",
      }, { plugin_name } )

      local service1 = bp.services:insert{
        protocol = "http",
        host     = "going.nowhere.a.company.xyz",
        port     = 12345,
        path     = "/something/weird/that/doesnt/exist/either",
      }


      local service2 = bp.services:insert{
        protocol = "http",
        host     = helpers.mock_upstream_hostname,
        port     = helpers.mock_upstream_port,
        path     = "/"
      }


      do -- plugin injecting values as plain values
        local route1 = bp.routes:insert {
          hosts   = { "plain_test.test" },
          service = service1
        }
        bp.plugins:insert {
          route = { id = route1.id },
          name = plugin_name,
          config = {
            path = "/request",
            host = helpers.mock_upstream_hostname,
            port = tostring(helpers.mock_upstream_port),
          }
        }
      end


      do -- plugin injecting values as a template
        local route2 = bp.routes:insert {
          hosts   = { "template_test.test" },
          service = service1
        }
        -- 2 plugins:
        -- pre-function: plugin to inject a shared value in the kong.ctx.shared table
        -- transformer: pick up the values and inject them in the router
        bp.plugins:insert {
          route = { id = route2.id },
          name = "pre-function",
          config = {
            access = {
              [[
                kong.ctx.shared.test_path = "/request"
                kong.ctx.shared.test_host = "]] .. helpers.mock_upstream_hostname .. [["
                kong.ctx.shared.test_port = "]] .. helpers.mock_upstream_port .. [["
              ]]
            },
          }
        }
        bp.plugins:insert {
          route = { id = route2.id },
          name = plugin_name,
          config = {
            path = "$(shared.test_path)",
            port = "$(shared.test_port)",
            host = "$(shared.test_host)",
          }
        }
      end


      do -- partial, do not set path
        local route3 = bp.routes:insert {
          hosts   = { "partial_test.test" },
          service = service1
        }
        bp.plugins:insert {
          route = { id = route3.id },
          name = plugin_name,
          config = {
            --path = "/request",
            host = helpers.mock_upstream_hostname,
            port = tostring(helpers.mock_upstream_port),
          }
        }
      end


      do -- path contains whitespace
        local route4 = bp.routes:insert {
          hosts   = { "path_whitespace_test.test" },
          service = service2
        }
        bp.plugins:insert {
          route = { id = route4.id },
          name = plugin_name,
          config = {
            path = "/request/a a",
            escape_path = true,
          }
        }
      end


      do -- path already url-encoded, do not double escape it
        local route5 = bp.routes:insert {
          hosts   = { "double_escape_test.test" },
          service = service2
        }
        bp.plugins:insert {
          route = { id = route5.id },
          name = plugin_name,
          config = {
            path = "/request/a%20a",
            escape_path = true,
          }
        }
      end


      assert(helpers.start_kong({
        database = db_strategy,
        plugins = "bundled, " .. plugin_name,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      client = helpers.proxy_client()
    end)

    after_each(function()
      if client then client:close() end
    end)



    it("changes the route with plain values", function()
      local r = assert(client:send {
        method = "GET",
        path = "/",
        headers = {
          host = "plain_test.test"
        }
      })
      assert.response(r).has.status(200)
      local json = assert.response(r).has.jsonbody()
      assert.equal("/request", json.vars.uri)
    end)

    it("changes the route with templated values", function()
      local r = assert(client:send {
        method = "GET",
        path = "/",
        headers = {
          host = "template_test.test"
        }
      })
      assert.response(r).has.status(200)
      local json = assert.response(r).has.jsonbody()
      assert.equal("/request", json.vars.uri)
    end)

    it("changes the route without a path (partial update)", function()
      local r = assert(client:send {
        method = "GET",
        path = "/",
        headers = {
          host = "partial_test.test"
        }
      })
      assert.response(r).has.status(404)  -- 404 because path wasn't found
      local json = assert.response(r).has.jsonbody()
      assert.equal("/something/weird/that/doesnt/exist/either", json.vars.uri)
    end)

    it("changes the route with a path contains whitespace", function()
      local r = assert(client:send {
        method = "GET",
        path = "/",
        headers = {
          host = "path_whitespace_test.test"
        }
      })
      assert.response(r).has.status(200)
      local json = assert.response(r).has.jsonbody()
      assert.equal("/request/a%20a", json.vars.request_uri)
    end)

    it("the path already escaped, don't double escape it", function()
      local r = assert(client:send {
        method = "GET",
        path = "/",
        headers = {
          host = "double_escape_test.test"
        }
      })
      assert.response(r).has.status(200)
      local json = assert.response(r).has.jsonbody()
      assert.equal("/request/a%20a", json.vars.request_uri)
    end)
  end)

end  -- for loop: strategies
