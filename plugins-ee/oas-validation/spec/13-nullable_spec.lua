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
          server_name petstore.com;
          listen 12345;

          location / {
            content_by_lua_block {
              local body = ngx.req.get_headers()['X-Mock-Response']
              ngx.status = 200
              if body then
                ngx.header["Content-Type"] = "application/json"
                ngx.say(body)
              end
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
      }, { PLUGIN_NAME })

      local service1 = assert(bp.services:insert {
        protocol = "http",
        port = 12345,
        host = "127.0.0.1",
      })

      local route1 = assert(db.routes:insert({
        hosts = { "example.com" },
        service = service1,
      }))
      assert(db.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route1.id },
        config = {
          api_spec = fixture_path.read_fixture("openapi_3.0.yaml"),
          validate_response_body = true,
          validate_request_header_params = true,
          validate_request_query_params = true,
          validate_request_uri_params = true,
          header_parameter_check = true,
          query_parameter_check = true,
          verbose_response = true,
          allowed_header_parameters = "Host,Content-Type,User-Agent,Accept,Content-Length,X-Mock-Response"
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

    describe("nullable", function()
      it("accepts when passing 'null' for a schema with nullable properties defined", function()
        local res = assert(client:send {
          method = "POST",
          path = "/nullable/properties",
          headers = {
            host = "example.com",
            ["content-type"] = "application/json"
          },
          body = [[
          {
            "string_nullable": null,
            "integer_nullable": null,
            "boolean_nullable": null,
            "object_nullable": null
          }]]
        })
        assert.response(res).has.status(200)
      end)

      it("rejects when passing 'null' for a schema does not allow null", function()
        local res = assert(client:send {
          method = "POST",
          path = "/nullable/properties",
          headers = {
            host = "example.com",
            ["content-type"] = "application/json"
          },
          body = [[ null ]]
        })
        assert.response(res).has.status(400)
        local body = assert.response(res).has.jsonbody()
        assert.equal(body.message, "request body validation failed with error: 'wrong type: expected object, got null'")
      end)

      it("accepts when passing 'null' for a nullable object", function()
        local res = assert(client:send {
          method = "POST",
          path = "/nullable/object",
          headers = {
            host = "example.com",
            ["content-type"] = "application/json"
          },
          body = [[ null ]]
        })
        assert.response(res).has.status(200)
      end)

    end)

  end)
end
