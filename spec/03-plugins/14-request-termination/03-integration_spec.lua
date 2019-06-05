local helpers = require "spec.helpers"


for _, strategy in helpers.each_strategy() do
  describe("Plugin: request-termination (integration) [#" .. strategy .. "]", function()
    local proxy_client
    local admin_client
    local consumer

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
        "consumers",
        "keyauth_credentials",
      })

      bp.routes:insert({
        hosts = { "api1.request-termination.com" },
      })

      bp.plugins:insert {
        name = "key-auth",
      }

      consumer = bp.consumers:insert {
        username = "bob",
      }

      bp.keyauth_credentials:insert {
        key      = "kong",
        consumer = { id = consumer.id },
      }

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      proxy_client = helpers.proxy_client()
      admin_client = helpers.admin_client()
    end)

    lazy_teardown(function()
      if proxy_client and admin_client then
        proxy_client:close()
        admin_client:close()
      end
      helpers.stop_kong()
    end)

    it("can be applied on a consumer", function()
      -- add the plugin to a consumer
      local res = assert(admin_client:send {
        method  = "POST",
        path    = "/plugins",
        headers = {
          ["Content-type"] = "application/json",
        },
        body    = {
          name        = "request-termination",
          consumer = { id = consumer.id },
        },
      })
      assert.response(res).has.status(201)

      -- verify access being blocked
      res = assert(proxy_client:send {
        method  = "GET",
        path    = "/request",
        headers = {
          ["Host"]   = "api1.request-termination.com",
          ["apikey"] = "kong",
        },
      })
      assert.response(res).has.status(503)
      local body = assert.response(res).has.jsonbody()
      assert.same({ message = "Service unavailable" }, body)
    end)
  end)
end
