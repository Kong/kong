-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson"

local PLUGIN_NAME = "ai-azure-content-safety"
local MOCK_PORT = helpers.get_available_port()

-- REQUESTS
local _GENERIC_REQUEST = {
  messages = {
    [1] = {
      role = "system",
      content = "You are a mathematician."
    },
    [2] = {
      role = "user",
      content = "I hate you."
    },
  },
}
--


for _, strategy in helpers.all_strategies() do
  describe(PLUGIN_NAME .. ": (access) [#" .. strategy .. "]", function()
    local client

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy == "off" and "postgres" or strategy, nil, { PLUGIN_NAME })

      -- set up acs mock fixtures
      local fixtures = {
        http_mock = {},
      }

      fixtures.http_mock.acs = [[
        server {
          server_name acs;
          listen ]]..MOCK_PORT..[[;

          default_type 'application/json';

          location = "/good/contentsafety/text:analyze" {
            content_by_lua_block {
              local json = require("cjson.safe")

              ngx.status = 200
              ngx.print('{"blocklistsMatch": [],"categoriesAnalysis": [{"category": "Hate","severity": 0}]}')
            }
          }

          location = "/breaches_hate/contentsafety/text:analyze" {
            content_by_lua_block {
              local json = require("cjson.safe")

              ngx.status = 200
              ngx.print('{"blocklistsMatch": [],"categoriesAnalysis": [{"category": "Hate","severity": 2}]}')
            }
          }

          location = "/unauthorized/contentsafety/text:analyze" {
            content_by_lua_block {
              local json = require("cjson.safe")

              ngx.status = 401
              ngx.print('{"not": "allowed"}')
            }
          }
        }
      ]]

      -- Echo
      local echo_service = bp.services:insert({
        host = helpers.mock_upstream_host,
        port = helpers.mock_upstream_port,
        protocol = helpers.mock_upstream_protocol,
      })

      -- Good introspection
      local echo_route = bp.routes:insert({
        service = echo_service,
        hosts = { "passes.echo.konghq.test" },
      })

      bp.plugins:insert({
        name = PLUGIN_NAME,
        route = echo_route,
        config = {
          content_safety_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/good/contentsafety/text:analyze",
          azure_use_managed_identity = false,
          reveal_failure_reason = true,
          content_safety_key = "anything",
          categories = {
            [1] = {
              name = "Hate",
              rejection_level = 2,
            },
            [2] = {
              name = "Violence",
              rejection_level = 2,
            },
          },
        },
      })

      -- Fails 'Hate'
      local echo_route = bp.routes:insert({
        service = echo_service,
        hosts = { "breaches_hate.echo.konghq.test" },
      })
      bp.plugins:insert({
        name = PLUGIN_NAME,
        route = echo_route,
        config = {
          content_safety_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/breaches_hate/contentsafety/text:analyze",
          azure_use_managed_identity = false,
          reveal_failure_reason = true,
          content_safety_key = "anything",
          categories = {
            [1] = {
              name = "Hate",
              rejection_level = 2,
            },
            [2] = {
              name = "Violence",
              rejection_level = 2,
            },
          },
        },
      })

      -- Fails 'Hate'
      local echo_route = bp.routes:insert({
        service = echo_service,
        hosts = { "unauthorized.echo.konghq.test" },
      })
      bp.plugins:insert({
        name = PLUGIN_NAME,
        route = echo_route,
        config = {
          content_safety_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/unauthorized/contentsafety/text:analyze",
          azure_use_managed_identity = false,
          reveal_failure_reason = true,
          content_safety_key = "anything",
          categories = {
            [1] = {
              name = "Hate",
              rejection_level = 2,
            },
            [2] = {
              name = "Violence",
              rejection_level = 2,
            },
          },
        },
      })

      -- start kong
      assert(helpers.start_kong({
        -- set the strategy
        database   = strategy,
        -- use the custom test template to create a local mock server
        nginx_conf = "spec/fixtures/custom_nginx.template",
        -- make sure our plugin gets loaded
        plugins = "bundled," .. PLUGIN_NAME,
        -- write & load declarative config, only if 'strategy=off'
        declarative_config = strategy == "off" and helpers.make_yaml_file() or nil,
      }, nil, nil, fixtures))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)



    before_each(function()
      client = helpers.proxy_client()
    end)

    after_each(function()
      if client then client:close() end
    end)



    describe("azure content safety general", function()
      it("passes checks", function()
        local r = client:get("/", {
          headers = {
            ["host"] = "passes.echo.konghq.test",
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
          },
          body = cjson.encode(_GENERIC_REQUEST),
        })

        -- validate that the request succeeded, response status 200
        assert.res_status(200 , r)
      end)


      it("breaches hate", function()
        local r = client:get("/", {
          headers = {
            ["host"] = "breaches_hate.echo.konghq.test",
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
          },
          body = cjson.encode(_GENERIC_REQUEST),
        })

        -- validate that the request succeeded, response status 200
        assert.res_status(400 , r)
      end)


      it("unauthorized", function()
        local r = client:get("/", {
          headers = {
            ["host"] = "unauthorized.echo.konghq.test",
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
          },
          body = cjson.encode(_GENERIC_REQUEST),
        })

        -- validate that the request succeeded, response status 200
        assert.res_status(500 , r)
      end)

    end)

  end)

end
