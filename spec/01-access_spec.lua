local helpers = require "spec.helpers"
local version = require("version").version or require("version")


local PLUGIN_NAME = "mocking"


for _, strategy in helpers.each_strategy() do
  describe(PLUGIN_NAME .. ": (access) [#" .. strategy .. "]", function()
    local client
      
      lazy_setup(function()
        local users_apispec = assert(io.open("users_OASv2.yaml"))
        local bp = helpers.get_db_utils(strategy, {
          "routes",
          "services",
          "files",
        })

        local anonymous_user = bp.files:insert {
          path = "default:specs/users.yaml",
          content = "",
        }

      -- Inject a test route. No need to create a service, there is a default
      -- service which will echo the request.
      local route1 = bp.routes:insert({
        hosts = { "test1.com" },
      })
    
      local route2 = bp.routes:insert({
        hosts = { "mock-error.com" },
      })
      -- add the plugin to test to the route we created
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route1.id },
        config = {
          api_specification_filename = "users.yaml",
        },
      }
      
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route2.id },
        config = {
          api_specification_filename = "",
        },
      }

      -- start kong
      assert(helpers.start_kong({
        -- set the strategy
        database   = strategy,
        -- use the custom test template to create a local mock server
        nginx_conf = "spec/fixtures/custom_nginx.template",
        -- make sure our plugin gets loaded
        plugins = "bundled," .. PLUGIN_NAME,
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



    describe(PLUGIN_NAME.." ", function()
      it("gets a X-Kong-Mocking-Plugin header", function()
        local r = assert(client:send {
          method = "GET",
          path = "/request",  -- makes mockbin return the entire request
          headers = {
            host = "test1.com"
          }
        })
        -- validate that the request succeeded, response status 200
        --assert.response(r).has.status(200)
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        local upStreamHeaderVal  = json.headers["X-Kong-Mocking-Plugin"]
        assert.equal("true",upStreamHeaderVal)
      end)
    end)



    describe(PLUGIN_NAME.." ", function()
      it("Empty spec filename check", function()
        local r = assert(client:send {
          method = "GET",
          path = "/request",  -- makes mockbin return the entire request
          headers = {
            host = "mock-error.com"
          }
        })
        -- validate that the request succeeded, response status 200
        assert.res_status(404, res)
      
      end)
    end)

  end)
end
