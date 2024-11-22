-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"


for _, strategy in helpers.each_strategy() do
  describe("Plugin: redirect (integration) [#" .. strategy .. "]", function()
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
        hosts = { "api1.redirect.test" },
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
          name     = "redirect",
          config   = {
            location = "https://example.com/path?foo=bar",
          },
          consumer = { id = consumer.id },
        },
      })
      assert.response(res).has.status(201)

      -- verify access being blocked
      helpers.wait_until(function()
        res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"]   = "api1.redirect.test",
            ["apikey"] = "kong",
          },
        })
        return pcall(function()
          assert.response(res).has.status(301)
        end)
      end, 10)
      local header = assert.response(res).has.header("location")
      assert.equals("https://example.com/path?foo=bar", header)
    end)
  end)
end
