local plugin_name = "route-transformer-advanced"
local helpers = require "spec.helpers"

for _, strategy in helpers.each_strategy() do
  describe(plugin_name .. " [#" .. strategy .. "]", function()
    local client

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
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


      do -- plugin injecting values as plain values
        local route1 = bp.routes:insert {
          hosts   = { "plain_test.com" },
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
          hosts   = { "template_test.com" },
          service = service1
        }
        -- 2 plugins:
        -- pre-function: plugin to inject a shared value in the kong.ctx.shared table
        -- transformer: pick up the values and inject them in the router
        bp.plugins:insert {
          route = { id = route2.id },
          name = "pre-function",
          config = {
            functions = {
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
          hosts   = { "partial_test.com" },
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


      assert(helpers.start_kong({
        database = strategy,
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
          host = "plain_test.com"
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
          host = "template_test.com"
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
          host = "partial_test.com"
        }
      })
      assert.response(r).has.status(404)  -- 404 because path wasn't found
      local json = assert.response(r).has.jsonbody()
      assert.equal("/something/weird/that/doesnt/exist/either", json.vars.uri)
    end)

  end)

end  -- for loop: strategies
