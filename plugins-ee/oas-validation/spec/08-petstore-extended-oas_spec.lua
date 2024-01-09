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

          location ~ "/info" {
            return 200;
          }

          location ~ "/pets" {
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

      local service1 = bp.services:insert{
        protocol = "http",
        port     = 12345,
        host     = "127.0.0.1",
        path     = "/getPets"
      }

      local service2 = bp.services:insert{
        protocol = "http",
        port     = 12345,
        host     = "127.0.0.1",
        path     = "/info"
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
          api_spec = assert(io.open(helpers.get_fixtures_path() .. "/resources/petstore-expanded.json"):read("*a")),
          validate_request_query_params = true,
          validate_request_body = true,
          verbose_response = true
        },
      }

      db.plugins:insert {
        name = PLUGIN_NAME,
        service = { id = service2.id },
        route = { id = route2.id },
        config = {
          api_spec = assert(io.open(helpers.get_fixtures_path() .. "/resources/petstore-expanded.json"):read("*a")),
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

    describe("Petstore oas tests", function()
      it("/pets get - parameter can have style defined", function()
        local res = assert(client:send {
          method = "GET",
          path = "/pets?tags=tag1,tag2",
          headers = {
            host = "petstore1.test",
            ["Content-Type"] = "application/json",
          },
        })
        -- validate that the request succeeded, response status 200
        assert.response(res).has.status(200)
      end)

      it("/pets post - validate request body", function()
        local res = assert(client:send {
          method = "POST",
          path = "/pets",
          headers = {
            host = "petstore1.test",
            ["Content-Type"] = "application/json",
          },
          body = {
            name = "dog",
            tag = "tag1"
          }
        })
        -- validate that the request succeeded, response status 200
        assert.response(res).has.status(200)
      end)

      it("/info get - parameter can be deepObject", function()
        local res = assert(client:send {
          method = "GET",
          path = "/info?sort[field]=value1&sort[order]=value2",
          headers = {
            host = "petstore1.test",
            ["Content-Type"] = "application/json",
          },
        })
        -- validate that the request succeeded, response status 200
        assert.response(res).has.status(200)
      end)

      it("/info get - deepObject parameter with missing schema field", function()
        local res = assert(client:send {
          method = "GET",
          path = "/info?sort[field]=value1",
          headers = {
            host = "petstore1.test",
            ["Content-Type"] = "application/json",
          },
        })
        -- validate that the request succeeded, response status 200
        local body = assert.response(res).has.status(400)
        local json = cjson.decode(body)
        assert.same("query 'sort' validation failed with error: 'property order is required'", json.message)
      end)
    end)
  end)
end
