local helpers = require "spec.helpers"

local PLUGIN_NAME    = require("kong.plugins.exit-transformer").PLUGIN_NAME


for _, strategy in helpers.each_strategy() do
  describe(PLUGIN_NAME .. ": (scope) [#" .. strategy .. "]", function()
    local client, admin_client

    local bp, gplugin

    lazy_setup(function()
      bp = helpers.get_db_utils(strategy, nil, { PLUGIN_NAME })

      local function_str_body_hello_world = [[
        return function (status, body, headers)
          body = { hello = "world" }
          return status, body, headers
        end
      ]]

      local function_str_body_another = [[
        return function (status, body, headers)
          body = { another = "transform" }
          return status, body, headers
        end
      ]]

      -- Apply plugin globally
      gplugin = bp.plugins:insert {
        name = PLUGIN_NAME,
        config = {
          functions = { function_str_body_hello_world },
        }
      }

      -- Add a plugin that generates a kong.response.exit, such as key-auth
      -- with invalid or no credentials
      bp.plugins:insert {
        name = "key-auth",
      }

      bp.routes:insert({
        hosts = { "test1.com" },
      })

      local route2 = bp.routes:insert({
        hosts = { "test2.com" },
      })

      -- Add another instance of the plugin, just to the route
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route2.id },
        config = { functions = { function_str_body_another } },
      }

      -- start kong
      assert(helpers.start_kong({
        -- set the strategy
        database   = strategy,
        -- use the custom test template to create a local mock server
        nginx_conf = "spec/fixtures/custom_nginx.template",
        -- set the config item to make sure our plugin gets loaded
        plugins = "bundled," .. PLUGIN_NAME,  -- since Kong CE 0.14
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong(nil, true)
    end)

    before_each(function()
      client = helpers.proxy_client()
      admin_client = helpers.admin_client()
    end)

    after_each(function()
      if client then client:close() end
      if admin_client then admin_client:close() end
    end)

    describe("global scope", function()
      it("global plugin applies only if conf.handle_unknown", function()
        local res = assert(admin_client:send({
          method  = "PATCH",
          path    = "/plugins/" .. gplugin.id,
          body    = {
            config = { handle_unknown = true },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        }))
        assert.res_status(200, res)

        -- try a request to a route that does not exist
        local res = assert(client:send {
          method = "get",
          path = "/request",  -- makes mockbin return the entire request
          headers = {
            host = "non-set-route.com"
          }
        })

        local body = res:read_body()
        assert.equal("{\"hello\":\"world\"}", body)


        local res = assert(admin_client:send({
          method  = "PATCH",
          path    = "/plugins/" .. gplugin.id,
          body    = {
            config = { handle_unknown = false },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        }))
        assert.res_status(200, res)

        -- try a request to a route that does not exist
        local res = assert(client:send {
          method = "get",
          path = "/request",  -- makes mockbin return the entire request
          headers = {
            host = "non-set-route.com"
          }
        })

        assert.response(res).has.status(404)
        local body = res:read_body()
        assert.equal("{\"message\":\"no Route matched with those values\"}", body)

      end)

      it("plugin on route applies", function()
        local res = assert(client:send {
          method = "GET",
          path = "/request",  -- makes mockbin return the entire request
          headers = {
            host = "test1.com"
          }
        })
        local body = res:read_body()
        assert.equal("{\"hello\":\"world\"}", body)
      end)
    end)

    describe("specific", function()
      it("plugin with another instance of the plugin also applies", function()
        local res = assert(client:send {
          method = "get",
          path = "/request",  -- makes mockbin return the entire request
          headers = {
            host = "test2.com"
          }
        })

        local body = res:read_body()
        assert.equal("{\"another\":\"transform\"}", body)
      end)
    end)
  end)
end
