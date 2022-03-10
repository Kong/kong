local helpers    = require "spec.helpers"
local utils      = require "kong.tools.utils"
local inspect = require "inspect"

for _, strategy in helpers.each_strategy() do
  describe("Plugin: opentelemetry (log) [#" .. strategy .. "]", function()
    local proxy_client

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      })

      local route1 = bp.routes:insert {
        hosts = { "logging.com" },
      }

      bp.plugins:insert {
        route = { id = route1.id },
        name     = "opentelemetry",
        config   = {
          http_endpoint = "http://127.0.0.1:9090",
        },
      }

      local ok, _, stdout = helpers.execute("uname")
      assert(ok, "failed to retrieve platform name")

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      proxy_client = assert(helpers.proxy_client())
    end)

    after_each(function()
      if proxy_client then proxy_client:close() end
    end)

    local function do_test(host)
      local uuid = utils.uuid()
      local resp

      local response = assert(proxy_client:send {
        method  = "GET",
        path    = "/request",
        headers = {
          host = host,
        }
      })
      assert.res_status(200, response)
      return resp
    end

    it("tarcer spans", function ()
      do_test("logging.com")
      local spans = kong.tracer.spans
      print(inspect(spans))
    end)

  end)
end
