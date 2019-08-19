local helpers = require "spec.helpers"

local PLUGIN_NAME    = require("kong.plugins.exit-transformer").PLUGIN_NAME


for _, strategy in helpers.each_strategy() do
  describe(PLUGIN_NAME .. ": (access) [#" .. strategy .. "]", function()
    local client

    lazy_setup(function()
      local bp, route1

      local bp = helpers.get_db_utils(strategy, nil, { PLUGIN_NAME })

      local route1 = bp.routes:insert({
        hosts = { "test1.com" },
      })

      local function_str = [[
        return function (status, body, headers)
          body = { hello = "world" }
          return status, body, headers
        end
      ]]
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route1.id },
        config = { functions = { function_str } },
      }

      bp.plugins:insert {
        name = "key-auth",
        route = { id = route1.id },
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

    describe("response", function()
      it("gets a custom response instead of a kong error", function()
        local r = assert(client:send {
          method = "GET",
          path = "/request",  -- makes mockbin return the entire request
          headers = {
            host = "test1.com"
          }
        })
        local body = r:read_body()

        assert.equal("{\"hello\":\"world\"}", body)
      end)
    end)

  end)
end
