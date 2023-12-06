-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local pl_file = require "pl.file"
local helpers = require "spec.helpers"

local sandbox = require "kong.tools.sandbox"

local strategies = helpers.all_strategies ~= nil and helpers.all_strategies or helpers.each_strategy

local PLUGIN_NAME    = require("kong.plugins.exit-transformer").PLUGIN_NAME

for _, strategy in strategies() do
  describe(PLUGIN_NAME .. ": (handler) [#" .. strategy .. "]", function()
    local client, admin_client
    local db_strategy = strategy ~= "off" and strategy or nil

    local conf = {
      -- set the strategy
      database   = db_strategy,
      -- use the custom test template to create a local mock server
      nginx_conf = "spec/fixtures/custom_nginx.template",
      -- set the config item to make sure our plugin gets loaded
      plugins = "bundled," .. PLUGIN_NAME,  -- since Kong CE 0.14
    }

    lazy_setup(function()
      local bp = helpers.get_db_utils(db_strategy, nil, { PLUGIN_NAME })

      local route1 = bp.routes:insert({
        hosts = { "test1.test" },
      })

      local function_str_status = [[
        return function (status, body, headers)
          status = 418
          return status, body, headers
        end
      ]]

      local function_str_body_hello_world = [[
        return function (status, body, headers)
          body = { hello = "world" }
          return status, body, headers
        end
      ]]

      local function_str_headers = [[
        return function (status, body, headers)
          local headers = headers or {}
          headers["some-header"] = "some value"
          return status, body, headers
        end
      ]]

      local function_kong_ctx = [[
        return function (status, body, headers)
          local something = kong.request.get_header("something")
          return 418, something, headers
        end
      ]]

      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route1.id },
        config = { functions = { function_str_body_hello_world } },
      }

      -- Add a plugin that generates a kong.response.exit, such as key-auth
      -- with invalid or no credentials
      bp.plugins:insert {
        name = "key-auth",
        route = { id = route1.id },
      }

      local route2 = bp.routes:insert {
        hosts = { "test2.test" },
      }

      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route2.id },
        config = { functions = { function_str_headers } },
      }

      -- Add a plugin that generates a kong.response.exit, such as key-auth
      -- with invalid or no credentials
      bp.plugins:insert {
        name = "key-auth",
        route = { id = route2.id },
      }

      local route3 = bp.routes:insert {
        hosts = { "test3.test" },
      }

      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route3.id },
        config = { functions = { function_str_status } },
      }

      -- Add a plugin that generates a kong.response.exit, such as key-auth
      -- with invalid or no credentials
      bp.plugins:insert {
        name = "key-auth",
        route = { id = route3.id },
      }


      local route4 = bp.routes:insert {
        hosts = { "test4.test" },
      }

      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route4.id },
        config = { functions = { function_str_status, function_str_headers,
                                 function_str_body_hello_world } },
      }

      -- Add a plugin that generates a kong.response.exit, such as key-auth
      -- with invalid or no credentials
      bp.plugins:insert {
        name = "key-auth",
        route = { id = route4.id },
      }

      local route6 = bp.routes:insert {
        hosts = { "test6.test" },
      }

      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route6.id },
        config = { functions = { function_kong_ctx } },
      }

      -- Add a plugin that generates a kong.response.exit, such as key-auth
      -- with invalid or no credentials
      bp.plugins:insert {
        name = "key-auth",
        route = { id = route6.id },
      }


      -- Add a plugin that generates a kong.response.exit on access phase, to
      -- make sure the exit hook runs only once

      local route7 = bp.routes:insert {
        hosts = { "test7.test" },
      }

      bp.plugins:insert {
        name = "post-function",
        route = { id = route7.id },
        -- access phase uses delayed response
        config = { access = { [[ return function()
          kong.response.exit(418, { count = 0 })
        end ]] } }
      }

      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route7.id },
        config = { functions = { [[ return function(status, body, headers)
          return status, { count = body.count + 1 }, headers
        end ]] } },
      }

      -- Add a plugin that generates a kong.response.exit on a phase that does
      -- not use delayed response

      local route8 = bp.routes:insert {
        hosts = { "test8.test" },
      }

      bp.plugins:insert {
        name = "post-function",
        route = { id = route8.id },
        config = { header_filter = { [[ return function()
          kong.response.exit(418, { count = 0 })
        end ]] } }
      }

      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route8.id },
        config = { functions = { [[ return function(status, body, headers)
          return status, { count = body.count + 1 }, headers
        end ]] } },
      }

      -- start kong
      assert(helpers.start_kong(conf))
    end)

    lazy_teardown(function()
      helpers.stop_kong(nil, true)
    end)

    before_each(function()
      client = helpers.proxy_client()
      admin_client = helpers.admin_client()
    end)

    after_each(function()
      if client then client:close() end
    end)

    describe("untrusted_lua = 'off'", function()
      lazy_setup(function()
        conf.untrusted_lua = 'off'
        assert(helpers.stop_kong(nil, true))
        assert(helpers.start_kong(conf))
      end)

      lazy_teardown(function()
        conf.untrusted_lua = nil
      end)

      it("does gracefully do nothing and log error", function()
        local res = assert(client:send {
          method = "GET",
          path = "/request",  -- makes mockbin return the entire request
          headers = {
            host = "test1.test"
          }
        })
        assert.response(res).has.status(401)

        helpers.wait_until(function()
          local TEST_CONF = helpers.test_conf
          local logs = pl_file.read(TEST_CONF.prefix .. "/" .. TEST_CONF.proxy_error_log)

          local _, count = logs:gsub(sandbox.configuration.err_msg, "")
          return count >= 1
        end, 3, 1)
      end)
    end)

    describe("exit", function() for _, untrusted in ipairs({'on', 'sandbox'}) do describe(("untrusted_lua = '%s'"):format(untrusted), function()
      lazy_setup(function()
        conf.untrusted_lua = untrusted
        assert(helpers.stop_kong(nil, true))
        assert(helpers.start_kong(conf))
      end)

      lazy_teardown(function()
        conf.untrusted_lua = nil
      end)

      it("gets a custom exit instead of normal kong error", function()
        local res = assert(client:send {
          method = "GET",
          path = "/request",  -- makes mockbin return the entire request
          headers = {
            host = "test1.test"
          }
        })
        local body = res:read_body()
        assert.equal("{\"hello\":\"world\"}", body)
      end)

      it("adds headers to the response", function()
        local res = assert(client:send {
          method = "GET",
          path = "/request",  -- makes mockbin return the entire request
          headers = {
            host = "test2.test"
          }
        })
        local header = assert.response(res).has.header("some-header")
        assert.equal("some value", header)
      end)

      it("changes status code of the response", function()
        local res = assert(client:send {
          method = "GET",
          path = "/request",  -- makes mockbin return the entire request
          headers = {
            host = "test3.test"
          }
        })
        assert.response(res).has.status(418)
      end)

      it("transform functions are executed in chain", function()
        local res = assert(client:send {
          method = "GET",
          path = "/request",  -- makes mockbin return the entire request
          headers = {
            host = "test4.test"
          }
        })
        local body = assert.response(res).has.status(418)
        assert.equal("{\"hello\":\"world\"}", body)
        local header = assert.response(res).has.header("some-header")
        assert.equal("some value", header)
      end)

      it("has access to kong.request #pdk", function()
        local res = assert(client:send {
          method = "GET",
          path = "/request",  -- makes mockbin return the entire request
          headers = {
            host = "test6.test",
            something = "hello world",
          }
        })
        local body = res:read_body()
        assert.equal("hello world", body)
      end)

      -- https://konghq.atlassian.net/browse/FTI-2412
      -- XXX honestly, we want this to happen for _any_ phase
      -- OTT: seems busted does not accept tags with dashes.
      describe("does run the exit hook only once #FTI2412", function()
        it("on delayed responses", function()
          local res = assert(client:send {
            method = "GET",
            path = "/request",  -- makes mockbin return the entire request
            headers = {
              host = "test7.test",
              something = "hello world",
            }
          })
          local body = assert.response(res).has.status(418)
          assert.equal("{\"count\":1}", body)
        end)

        it("on non delayed responses", function()
          local res = assert(client:send {
            method = "GET",
            path = "/request",  -- makes mockbin return the entire request
            headers = {
              host = "test8.test",
              something = "hello world",
            }
          })
          local body = assert.response(res).has.status(418)
          assert.equal("{\"count\":1}", body)
        end)
      end)

      -- https://konghq.atlassian.net/browse/FTI-4073
      describe("does not affect CORS function of admin API", function()
        it("related headers of CORS request must present", function()
          local res = assert(admin_client:send {
            method = "OPTIONS",
            path = "/services",
          })
          assert.res_status(204, res)
          assert.not_nil(res.headers["Access-Control-Allow-Methods"])
          assert.not_nil(res.headers["Allow"])
        end)
      end)
    end) end end)
  end)
end
