local helpers = require "spec.helpers"
local cjson   = require "cjson"

for _, strategy in helpers.each_strategy() do
  describe("Collect plugin errors [#" .. strategy .. "]", function()
    local client

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      },{
        "logger"
      })

      local service = assert(bp.services:insert {
        url = helpers.mock_upstream_url
      })

      local route = assert(bp.routes:insert {
        service = service,
        hosts = { "error.test" }
      })

      assert(bp.plugins:insert {
        name = "error-generator",
        route = { id = route.id },
        config = {
          access = true,
        },
      })
      assert(bp.plugins:insert {
        name = "logger",
        route = { id = route.id },
      })

      assert(helpers.start_kong({
        database   = strategy,
        plugins    = "bundled, error-generator, logger",
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
      client = helpers.proxy_client()
    end)

    lazy_teardown(function()
      if client then
        client:close()
      end
      helpers.stop_kong()
    end)

    it("delays the error response", function()
      local res = assert(client:get("/get", {
        headers = {
          Host = "error.test",
        }
      }))
      local body = assert.res_status(500, res)
      local json = cjson.decode(body)
      assert.same({ message = "An unexpected error occurred" }, json)
      -- the other plugin's phases were executed:
      assert.logfile().has.line("header_filter phase", true)
      assert.logfile().has.line("body_filter phase", true)
      assert.logfile().has.line("log phase", true)
    end)
  end)
end
