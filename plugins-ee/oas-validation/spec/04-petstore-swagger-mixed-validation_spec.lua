-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers   = require "spec.helpers"
local cjson     = require("cjson.safe").new()
local fixture_path  = require("spec.fixtures.fixture_path")

local PLUGIN_NAME = "oas-validation"

local fixtures = {
  http_mock = {
    validation_plugin = [[
      server {
          server_name petstore.test;
          listen 12345;

          location ~ "/findByStatus-request-good" {
            content_by_lua_block {
              local body = require("pl.file").read(ngx.config.prefix() .. "/../spec/fixtures/petstore-findByStatus-response.json")
              ngx.status = 200
              ngx.header["Content-Type"] = "application/json"
              ngx.header["Content-Length"] = #body
              ngx.print(body)
            }
          }

          location ~ "/pet" {
            content_by_lua_block {
              local body = require("pl.file").read(ngx.config.prefix() .. "/../spec/fixtures/petstore-pet-response.json")
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
      }, { PLUGIN_NAME })

      local service1 = bp.services:insert{
        protocol = "http",
        port     = 12345,
        host     = "127.0.0.1",
        path     = "/findByStatus-request-good"
      }

      local service2 = bp.services:insert{
        protocol = "http",
        port     = 12345,
        host     = "127.0.0.1",
        path     = "/pet"
      }

      local route1 = db.routes:insert({
        hosts = { "petstore1.test" },
        service    = service1,
      })

      local route2 = db.routes:insert({
        hosts = { "petstore2.test" },
        service    = service2,
      })

    db.plugins:insert {
      name = PLUGIN_NAME,
      service = { id = service1.id },
      route = { id = route1.id },
      config = {
        api_spec = fixture_path.read_fixture("petstore-swagger.json"),
        verbose_response = true,
        validate_request_uri_params = false,
        validate_request_body = false,
        validate_request_header_params = false,
        validate_response_body = false,
        validate_request_query_params = false
      },
    }

    db.plugins:insert {
      name = PLUGIN_NAME,
      service = { id = service2.id },
      route = { id = route2.id },
      config = {
        api_spec = fixture_path.read_fixture("petstore-swagger.json"),
        verbose_response = true,
        validate_request_uri_params = true,
        validate_request_body = true,
        validate_request_header_params = true,
        validate_response_body = false,
        validate_request_query_params = true
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

    describe("Petstore v2 tests", function()
      it("/pet post - happy path", function()
        local res = assert(client:send {
          method = "POST",
          path = "/pet",
          headers = {
            host = "petstore2.test",
            ["Content-Type"] = "application/json",
          },
          body = {
            id = 0,
            category = {
              id = 99,
              name = "foo",
            },
            name = "doggie",
            photoUrls = {"string"},
            status = "available"
          }
        })
        -- validate that the request succeeded, response status 200
        assert.response(res).has.status(200)

      end)

      it("/pet post - missing name happy path", function()
        local res = assert(client:send {
          method = "POST",
          path = "/pet",
          headers = {
            host = "petstore2.test",
            ["Content-Type"] = "application/json",
          },
          body = {
            id = 0,
            category = {
              id = 99,
              name = "foo",
            },
            photoUrls = {"string"},
            status = "available"
          }
        })
        local body = assert.response(res).has.status(400)
        local json = cjson.decode(body)
        assert.same("body 'body' validation failed with error: 'property name is required'", json.message)

      end)

      it("/pet/findByStatus missing status path", function()
        local res = assert(client:send {
          method = "GET",
          path = "/pet/findByStatus",
          headers = {
            host = "petstore1.test",
            ["Content-Type"] = "application/json",
          },
          query = {
          }
        })
        -- validate that the request succeeded, response status 200
        assert.response(res).has.status(200)

      end)

      it("get /pet/1 wrong type for uri parameter", function()
        local res = assert(client:send {
          method = "GET",
          path = "/pet/string123",
          headers = {
            host = "petstore2.test",
            ["Content-Type"] = "application/json",
          },
        })
        local body = assert.response(res).has.status(400)
        local json = cjson.decode(body)
        assert.same("path 'petId' validation failed with error: 'wrong type: expected integer, got string'", json.message)
        --
      end)


    end)

  end)
end
