-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson   = require "cjson"

for _, strategy in helpers.each_strategy() do
  describe("Plugin: key-auth (EE) (access) [#" .. strategy .. "]", function()
    local proxy_client

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
        "consumers",
        "keyauth_credentials",
      })

      local consumer = bp.consumers:insert {
        username = "bob"
      }

      local route1 = bp.routes:insert {
        hosts = { "key-auth1.test" },
      }

      local route2 = bp.routes:insert {
        hosts = { "key-auth2.test" },
      }

      bp.plugins:insert {
        name     = "key-auth",
        route = { id = route1.id },
        config = {
          key_in_body = true,
          hide_credentials = false,
        }
      }

      bp.plugins:insert {
        name     = "key-auth",
        route = { id = route2.id },
        config = {
          key_in_body = true,
          hide_credentials = true,
        }
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
    end)
    lazy_teardown(function()
      if proxy_client then
        proxy_client:close()
      end

      helpers.stop_kong()
    end)

    -- FT-891
    local cases = {
      function()
        return "invalid", "invalid/l33t"
      end,
      function()
        return "empty", nil
      end,
    }
    for _, ctype_getter in pairs(cases) do
      local name, ctype = ctype_getter()
      describe("key_in_body fallback with " .. name .. " content-type", function()
        it("no invalid content type error message", function()
          local res = assert(proxy_client:send {
            path = "/status/200",
            headers = {
              ["Host"] = "key-auth1.test",
              ["Content-Type"] = ctype
            },
            body = "foobar",
          })
          local body = assert.res_status(401, res)
          local json = cjson.decode(body)
          assert.not_nil(json)
          assert.same("No API key found in request", json.message)
        end)

        it("looks for key in header", function()
          local res = assert(proxy_client:send {
            path = "/status/200",
            headers = {
              ["Host"] = "key-auth1.test",
              ["apikey"] = "kong",
              ["Content-Type"] = ctype
            },
            body = "foobar",
          })
          assert.res_status(200, res)
        end)

        it("looks for key in get arg", function()
          local res = assert(proxy_client:send {
            path = "/status/200?apikey=kong",
            headers = {
              ["Host"] = "key-auth1.test",
              ["Content-Type"] = ctype
            },
            body = "foobar",
          })
          assert.res_status(200, res)
        end)

        it("leaves body untouched even with hide_credentials", function()
          local res = assert(proxy_client:send {
            path = "/request?apikey=kong",
            headers = {
              ["Host"] = "key-auth2.test",
              ["Content-Type"] = ctype
            },
            body = "foobar",
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.equal("foobar", json.post_data.text)
        end)
      end)
    end
  end)
end
