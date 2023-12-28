local helpers = require "spec.helpers"

for _, strategy in helpers.each_strategy() do
  describe("cjson.new encode number with a precision of 16 decimals [#" .. strategy .. "]", function()
    local proxy_client

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      }, { "pre-function" })

      local route = bp.routes:insert({
        paths = { "/route_with_max_safe_integer_priority"},
      })

      bp.plugins:insert {
        route = { id = route.id },
        name = "pre-function",
        config = {
          access = {
            [[
              local cjson = require("cjson").new()
              ngx.say(cjson.encode({ n = 9007199254740992 }))
            ]]
          },
        }
      }

      assert(helpers.start_kong({
        database = strategy,
        untrusted_lua = "on",
        plugins = "bundled",
        nginx_conf = "spec/fixtures/custom_nginx.template",
        nginx_worker_processes = 1
      }))

      proxy_client = helpers.proxy_client()
    end)

    lazy_teardown(function()
      if proxy_client then
        proxy_client:close()
      end

      helpers.stop_kong()
    end)

    it("the maximum safe integer can be accurately represented as a decimal number", function()
      local res = assert(proxy_client:send {
        method = "GET",
        path   = "/route_with_max_safe_integer_priority"
      })

      assert.res_status(200, res)
      assert.match_re(res:read_body(), "9007199254740992")
    end)
  end)
end
