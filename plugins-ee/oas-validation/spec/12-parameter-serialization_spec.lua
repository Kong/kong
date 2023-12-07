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
          api_spec = fixture_path.read_fixture("parameter-serialization-oas.yaml"),
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

    describe("When spec parameters contains ref schema", function()
      it("should dereference ref schema for form style", function()
        local res = assert(client:send {
          method = "GET",
          path = "/query/form?string_ref=value",
          headers = {
            host = "example.com",
          },
        })
        assert.response(res).has.status(200)

        local res = assert(client:send {
          method = "GET",
          path = "/query/form?string_ref=aaaaaaaaaaa",
          headers = {
            host = "example.com",
          },
        })
        assert.response(res).has.status(400)
        local body = assert.response(res).has.jsonbody()
        assert.equal("query 'string_ref' validation failed with error: 'string too long, expected at most 10, got 11'", body.message)

        local res = assert(client:send {
          method = "GET",
          path = "/query/form?integer_ref=1",
          headers = {
            host = "example.com",
          },
        })
        assert.response(res).has.status(200)

        local res = assert(client:send {
          method = "GET",
          path = "/query/form?integer_ref=-1",
          headers = {
            host = "example.com",
          },
        })
        assert.response(res).has.status(400)
        local body = assert.response(res).has.jsonbody()
        assert.equal("query 'integer_ref' validation failed with error: 'expected -1 to be greater than 0'", body.message)
      end)
    end)

  end)
end
