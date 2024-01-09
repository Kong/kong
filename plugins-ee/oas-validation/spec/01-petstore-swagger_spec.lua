-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers   = require "spec.helpers"
local cjson     = require("cjson.safe").new()

local PLUGIN_NAME = "oas-validation"

local fixtures = {
  http_mock = {
    validation_plugin = [[
      server {
          server_name petstore.test;
          listen 12345;

          location ~ "/findByStatus-request-good" {
            content_by_lua_block {
              local body = require("pl.file").read("]] .. helpers.get_fixtures_path() .. [[/petstore-findByStatus-response.json")
              ngx.status = 200
              ngx.header["Content-Type"] = "application/json"
              ngx.header["Content-Length"] = #body
              ngx.print(body)
            }
          }

          location ~ "/pet" {
            content_by_lua_block {
              local body = require("pl.file").read("]] .. helpers.get_fixtures_path() .. [[/petstore-pet-response.json")
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
          path     = "/findByStatus-request-good"
        }

        local service2 = bp.services:insert{
          protocol = "http",
          port     = 12345,
          host     = "127.0.0.1",
          path     = "/pet"
        }

        local service3 = bp.services:insert{
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

        local route3 = db.routes:insert({
          hosts = { "petstore3.test" },
          service    = service3,
        })


      db.plugins:insert {
        name = PLUGIN_NAME,
        service = { id = service1.id },
        route = { id = route1.id },
        config = {
          api_spec = assert(io.open(helpers.get_fixtures_path() .. "/resources/petstore-swagger.json"):read("*a")),
          validate_response_body = true,
          verbose_response = true
        },
      }

      db.plugins:insert {
        name = PLUGIN_NAME,
        service = { id = service2.id },
        route = { id = route2.id },
        config = {
          api_spec = assert(io.open(helpers.get_fixtures_path() .. "/resources/petstore-swagger.json"):read("*a")),
          validate_response_body = true,
          verbose_response = true
        },
      }

      db.plugins:insert {
        name = PLUGIN_NAME,
        service = { id = service3.id },
        route = { id = route3.id },
        config = {
          api_spec = assert(io.open(helpers.get_fixtures_path() .. "/resources/petstore-swagger.json"):read("*a")),
          validate_response_body = true,
          verbose_response = true,
          validate_request_body = false
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
              name = "foo"
            },
            name = "doggie",
            photoUrls = {"string"},
            status = "available"
          }
        })
        -- validate that the request succeeded, response status 200
        assert.response(res).has.status(200)

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
        local body = assert.response(res).has.status(400)
        local json = cjson.decode(body)
        assert.same("query 'status' validation failed with error: 'required parameter value not found in request'", json.message)

      end)

      it("/pet/findByStatus single status value", function()
        local res = assert(client:send {
          method = "GET",
          path = "/pet/findByStatus",
          headers = {
            host = "petstore1.test",
            ["Content-Type"] = "application/json",
          },
          query = {
            status = "available",
          }
        })
        -- validate that the request succeeded, response status 200
        assert.response(res).has.status(200)

      end)

      it("get /pet/1 happy path", function()
        local res = assert(client:send {
          method = "GET",
          path = "/pet/1",
          headers = {
            host = "petstore2.test",
            ["Content-Type"] = "application/json",
          },
        })
        -- validate that the request succeeded, response status 200
        assert.response(res).has.status(200)

      end)

      it("get /pet/1/ path not defined in schema", function()
        local res = assert(client:send {
          method = "GET",
          path = "/pet/1/",
          headers = {
            host = "petstore2.test",
            ["Content-Type"] = "application/json",
          },
        })
        local body = assert.response(res).has.status(400)
        local json = cjson.decode(body)
        assert.same("validation failed, path not found in api specification", json.message)
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
      end)

      it("/pet post - invalid json body - missing name", function()
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
              name = "foo"
            },
            name = "doggie",
            photoUrls = {"string"},
            status = "none"
          }
        })
       local body = assert.response(res).has.status(400)
       local json = cjson.decode(body)
       assert.same("body 'body' validation failed with error: 'property status validation failed: matches none of the enum values'", json.message)
      end)

      it("/pet put - invalid json body - missing name", function()
        local res = assert(client:send {
          method = "PUT",
          path = "/pet",
          headers = {
            host = "petstore2.test",
            ["Content-Type"] = "application/json",
          },
          body = {
            id = 0,
            category = {
              id = 99,
              name = "foo"
            },
            name = "doggie",
            photoUrls = {"string"},
            status = "none"
          }
        })
       local body = assert.response(res).has.status(400)
       local json = cjson.decode(body)
       assert.same("body 'body' validation failed with error: 'property status validation failed: matches none of the enum values'", json.message)
      end)

      it("/pet put - invalid content-type", function()
        local res = assert(client:send {
          method = "PUT",
          path = "/pet",
          headers = {
            host = "petstore2.test",
            ["Content-Type"] = "application/json+1",
          },
          body = {
            id = 0,
            category = {
              id = 99,
              name = "foo"
            },
            name = "doggie",
            photoUrls = {"string"},
            status = "available"
          }
        })
       local body = assert.response(res).has.status(400)
       local json = cjson.decode(body)
       assert.same("validation failed: content-type 'application/json+1' is not supported", json.message)
      end)

      it("should pass the validation when passing a unallowed content-type while validate_request_body is disabled", function()
        local res = assert(client:send {
          method = "POST",
          path = "/pet",
          headers = {
            host = "petstore3.test",
            ["Content-Type"] = "application/pdf",
          },
        })
        assert.response(res).has.status(200)
      end)
    end)

  end)
end
