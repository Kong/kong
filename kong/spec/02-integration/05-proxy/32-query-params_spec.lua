local helpers = require "spec.helpers"
local cjson   = require "cjson"

for _, strategy in helpers.each_strategy() do
  describe("query args specs [#" .. strategy .. "]", function()
    local proxy_client

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "plugins",
        "routes",
        "services",
      })

      local service = assert(bp.services:insert({
        url = helpers.mock_upstream_url
      }))

      local route = assert(bp.routes:insert({
        service = service,
        paths = { "/set-query-arg" }
      }))

      assert(bp.plugins:insert({
        name = "request-transformer",
        route = { id = route.id },
        config = {
          add = {
            querystring = {"dummy:1"},
          },
        },
      }))

      helpers.start_kong({
        database = strategy,
        plugins = "bundled",
        nginx_conf = "spec/fixtures/custom_nginx.template",
      })
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

    it("does proxy set query args if URI does not contain arguments", function()
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/set-query-arg?",
        headers = {
          ["Host"] = "mock_upstream",
        },
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.equal("1", json.uri_args.dummy)
    end)
  end)
end
