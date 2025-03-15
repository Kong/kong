local helpers = require "spec.helpers"
local cjson = require "cjson"

local PLUGIN_NAME = "http-logger"

for _, strategy in helpers.each_strategy() do
  describe(PLUGIN_NAME .. ": (log) [#" .. strategy .. "]", function()
    local proxy_client
    
    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      })

      local route = bp.routes:insert {
        hosts = { "http_logger.test" },
      }

      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route.id },
        config = {
          http_endpoint = "http://" .. helpers.mock_upstream_host
                                    .. ":"
                                    .. helpers.mock_upstream_port
                                    .. "/post_log/http_logger",
        },
      }

      assert(helpers.start_kong({
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      proxy_client = helpers.proxy_client()
    end)

    after_each(function()
      if proxy_client then
        proxy_client:close()
      end
    end)

    it("logs to HTTP endpoint", function()
      local res = proxy_client:get("/status/200", {
        headers = {
          ["Host"] = "http_logger.test"
        }
      })
      assert.res_status(200, res)
      
      -- Wait for the log to be consumed
      helpers.wait_until(function()
        local client = helpers.http_client(helpers.mock_upstream_host,
                                          helpers.mock_upstream_port)
        local res = client:get("/count_log/http_logger", {
          headers = {
            Accept = "application/json"
          }
        })
        
        local count = tonumber(res:read_body())
        client:close()
        
        return count and count > 0
      end, 10)
    end)
  end)
end
