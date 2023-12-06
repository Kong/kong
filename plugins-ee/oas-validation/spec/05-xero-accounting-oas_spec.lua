-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers       = require "spec.helpers"
local cjson         = require("cjson.safe").new()
local fixture_path  = require("spec.fixtures.fixture_path")

local PLUGIN_NAME = "oas-validation"

local fixtures = {
  http_mock = {
    validation_plugin = [[
      server {
          server_name xero.test;
          listen 12345;

          location ~ "/request-good" {
            content_by_lua_block {
              local body = require("pl.file").read(ngx.config.prefix() .. "/../spec/fixtures/xero-response.json")
              ngx.status = 200
              ngx.header["Content-Type"] = "application/json"
              ngx.header["Content-Length"] = #body
              ngx.print(body)
            }
          }

          location ~ "/request-bad" {
            content_by_lua_block {
              local body = require("pl.file").read(ngx.config.prefix() .. "/../spec/fixtures/xero-invalid-response.json")
              ngx.status = 200
              ngx.header["Content-Type"] = "application/json"
              ngx.header["Content-Length"] = #body
              ngx.print(body)
            }
          }
        }
    ]]
  }
}

for _, strategy in helpers.each_strategy() do
  describe(PLUGIN_NAME .. ": (access) [#" .. strategy .. "]", function()
    local client

      lazy_setup(function()
        local bp, db = helpers.get_db_utils(strategy, {
          "routes",
          "services",
          "files",
        }, { PLUGIN_NAME })

        local service1 = bp.services:insert{
          protocol = "http",
          port     = 12345,
          host     = "127.0.0.1",
          path     = "/request-good"
        }

        local service2 = bp.services:insert{
          protocol = "http",
          port     = 12345,
          host     = "127.0.0.1",
          path     = "/request-bad"
        }

        local route1 = db.routes:insert({
          hosts = { "xero-good.test" },
          paths = { "/" },
          service    = service1,
        })

        local route2 = db.routes:insert({
          hosts = { "xero-bad.test" },
          paths = { "/" },
          service    = service2,
        })

      -- add the plugin to test to the route we created
      db.plugins:insert {
        name = PLUGIN_NAME,
        service = { id = service1.id },
        route = { id = route1.id },
        config = {
          api_spec = fixture_path.read_fixture("xero-finance-oas.yaml"),
          validate_response_body = true,
          verbose_response = true
        },
      }

      db.plugins:insert {
        name = PLUGIN_NAME,
        service = { id = service2.id },
        route = { id = route2.id },
        config = {
          api_spec = fixture_path.read_fixture("xero-finance-oas.yaml"),
          validate_response_body = true,
          verbose_response = true
        },
      }

      -- start kong
      assert(helpers.start_kong({
        -- set the strategy
        database   = strategy,
        -- use the custom test template to create a local mock server
        nginx_conf = "spec/fixtures/custom_nginx.template",
        -- make sure our plugin gets loaded
        plugins = "bundled," .. PLUGIN_NAME,
      }, nil, nil, fixtures))
    end)

    lazy_teardown(function()
      helpers.stop_kong(nil, true)
    end)

    before_each(function()
      client = helpers.proxy_client()
    end)

    after_each(function()
      if client then client:close() end
    end)

    describe("Xero Accounting API Specification tests", function()
      it("/FinancialStatements/contacts/revenue - valid response body", function()
        local res = assert(client:send {
          method = "GET",
          path = "/FinancialStatements/contacts/revenue",
          headers = {
            host = "xero-good.test",
            ["Content-Type"] = "application/json",
            ["xero-tenant-id"] = "12345",
          }
        })
        -- validate that the request succeeded, response status 200
        assert.response(res).has.status(200)

      end)

      it("/FinancialStatements/contacts/revenue - invalid response body -  contactId replaced with id", function()
        local res = assert(client:send {
          method = "GET",
          path = "/FinancialStatements/contacts/revenue",
          headers = {
            host = "xero-bad.test",
            ["Content-Type"] = "application/json",
            ["xero-tenant-id"] = "12345",
          }
        })
        local body = assert.response(res).has.status(406)
        local json = cjson.decode(body)
        assert.same("response body validation failed with error: property contacts validation failed: failed to validate item 1: additional properties forbidden, found id", json.message)

      end)


    end)

  end)
end
