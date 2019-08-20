local helpers = require "spec.helpers"

local PLUGIN_NAME    = require("kong.plugins.exit-transformer").PLUGIN_NAME


for _, strategy in helpers.each_strategy() do
  describe(PLUGIN_NAME .. ": (handler) [#" .. strategy .. "]", function()
    local client

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, nil, { PLUGIN_NAME })

      local route1 = bp.routes:insert({
        hosts = { "test1.com" },
      })

      local function_str_status = [[
        return function (status, body, headers)
          status = 418
          return status, body, headers
        end
      ]]

      local function_str_body_hello_world = [[
        return function (status, body, headers)
          body = { hello = "world" }
          return status, body, headers
        end
      ]]

      local function_str_headers = [[
        return function (status, body, headers)
          local headers = headers or {}
          headers["some-header"] = "some value"
          return status, body, headers
        end
      ]]

      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route1.id },
        config = { functions = { function_str_body_hello_world } },
      }

      -- Add a plugin that generates a kong.response.exit, such as key-auth
      -- with invalid or no credentials
      bp.plugins:insert {
        name = "key-auth",
        route = { id = route1.id },
      }

      local route2 = bp.routes:insert {
        hosts = { "test2.com" },
      }

      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route2.id },
        config = { functions = { function_str_headers } },
      }

      -- Add a plugin that generates a kong.response.exit, such as key-auth
      -- with invalid or no credentials
      bp.plugins:insert {
        name = "key-auth",
        route = { id = route2.id },
      }

      local route3 = bp.routes:insert {
        hosts = { "test3.com" },
      }

      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route3.id },
        config = { functions = { function_str_status } },
      }

      -- Add a plugin that generates a kong.response.exit, such as key-auth
      -- with invalid or no credentials
      bp.plugins:insert {
        name = "key-auth",
        route = { id = route3.id },
      }


      local route4 = bp.routes:insert {
        hosts = { "test4.com" },
      }


      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route4.id },
        config = { functions = { function_str_status, function_str_headers,
                                 function_str_body_hello_world } },
      }

      -- Add a plugin that generates a kong.response.exit, such as key-auth
      -- with invalid or no credentials
      bp.plugins:insert {
        name = "key-auth",
        route = { id = route4.id },
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
    end)

    after_each(function()
      if client then client:close() end
    end)

    describe("exit", function()
      it("gets a custom exit instead of normal kong error", function()
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

      it("adds headers to the response", function()
        local res = assert(client:send {
          method = "GET",
          path = "/request",  -- makes mockbin return the entire request
          headers = {
            host = "test2.com"
          }
        })
        local header = assert.response(res).has.header("some-header")
        assert.equal("some value", header)
      end)

      it("changes status code of the response", function()
        local res = assert(client:send {
          method = "GET",
          path = "/request",  -- makes mockbin return the entire request
          headers = {
            host = "test3.com"
          }
        })
        assert.response(res).has.status(418)
      end)

      it("transform functions are executed in chain", function()
        local res = assert(client:send {
          method = "GET",
          path = "/request",  -- makes mockbin return the entire request
          headers = {
            host = "test4.com"
          }
        })
        local body = assert.response(res).has.status(418)
        assert.equal("{\"hello\":\"world\"}", body)
        local header = assert.response(res).has.header("some-header")
        assert.equal("some value", header)
      end)
    end)
  end)
end
