-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local fixture_path = require("spec.fixtures.fixture_path")

local PLUGIN_NAME = "oas-validation"

local fixtures = {
  http_mock = {
    validation_plugin = [[
      server {
          server_name test.com;
          listen 12345;

          location ~ "/notify" {
            return 200;
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
      }, { PLUGIN_NAME })

      local service1 = bp.services:insert {
        protocol = "http",
        port = 12345,
        host = "127.0.0.1",
      }

      local route1 = db.routes:insert({
        hosts = { "test.com" },
        service = service1,
      })

      assert(db.plugins:insert {
        name = PLUGIN_NAME,
        service = { id = service1.id },
        route = { id = route1.id },
        config = {
          api_spec = fixture_path.read_fixture("request-body-oas.yaml"),
          validate_request_body = true,
        },
      })

      assert(helpers.start_kong({
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
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
      if client then
        client:close()
      end
    end)

    describe("request-body", function()
      it("/notify post - requests with no body should pass the validation when operation has no requestBody defined", function()
        local res = assert(client:send {
          method = "POST",
          path = "/notify",
          headers = {
            host = "test.com",
          },
        })
        assert.response(res).has.status(200)
      end)

      it("/notify post - requests with body should pass the validation when operation has no requestBody defined", function()
        local res = assert(client:send {
          method = "POST",
          path = "/notify",
          headers = {
            host = "test.com",
            ["Content-Type"] = "application/json",
          },
          body = {
            name = "value",
          }
        })
        assert.response(res).has.status(200)
      end)
    end)
  end)
end
