-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson"

local PLUGIN_NAME = "oas-validation"

local fixtures = {
  http_mock = {
    validation_plugin = [[
      server {
          listen 12345;

          location = "/with_charset" {
            content_by_lua_block {
              local req_headers = ngx.req.get_headers()
              if req_headers['x-charset'] then
                ngx.header["Content-Type"] = "application/json; charset=utf-8"
              else
                ngx.header["Content-Type"] = "application/json"
              end
              ngx.status = 200
              ngx.print('{"key": "string"}')
            }
          }
          
          location = "/without_charset" {
            content_by_lua_block {
              local req_headers = ngx.req.get_headers()
              if req_headers['x-charset'] then
                ngx.header["Content-Type"] = "application/json; charset=utf-8"
              else
                ngx.header["Content-Type"] = "application/json"
              end
              ngx.status = 200
              ngx.print('{"key": "string"}')
            }
          }
      }
    ]]
  }
}

for _, strategy in helpers.each_strategy() do
  describe(PLUGIN_NAME .. ": (response) [#" .. strategy .. "]", function()
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
        hosts = { "test1.test" },
        service = service1,
      }))
      assert(db.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route1.id },
        config = {
          api_spec = assert(io.open(helpers.get_fixtures_path() .. "/resources/response-body-validation.yaml"):read("*a")),
          validate_response_body = true,
          verbose_response = true,
        },
      })

      assert(helpers.start_kong({
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "bundled," .. PLUGIN_NAME,
      }, nil, nil, fixtures))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      client = helpers.proxy_client()
    end)

    after_each(function()
      if client then
        client:close()
      end
    end)

    describe("response validation", function()
      it("spec location by content-type", function()
        local res = assert(client:send {
          path = "/with_charset",
          headers = { 
            host = "test1.test",
            ["x-charset"] = true,
          },
        })
        assert.response(res).has.status(200)

        res = assert(client:send {
          path = "/with_charset",
          headers = { host = "test1.test", },
        })
        local body = cjson.decode(assert.res_status(406, res))
        assert.equal("response body validation failed with error: property foo is required", body.message)

        res = assert(client:send {
          path = "/without_charset",
          headers = { 
            host = "test1.test",
            ["x-charset"] = true,
          },
        })
        assert.response(res).has.status(200)

        res = assert(client:send {
          path = "/without_charset",
          headers = { host = "test1.test", },
        })
        assert.response(res).has.status(200)
      end)
    end)
  end)
end
