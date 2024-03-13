-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"

local PLUGIN_NAME = "oas-validation"

local fixtures = {
  http_mock = {
    validation_plugin = [[
      server {
          server_name petstore.test;
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
          api_spec = ngx.escape_uri(io.open(helpers.get_fixtures_path() .. "/resources/openapi_3.0.yaml"):read("*a")),
          verbose_response = true,
          api_spec_encoded = true,
          allowed_header_parameters = "Host,Content-Type,User-Agent,Accept,Content-Length,X-Mock-Response",
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

    it("should works when api_spec is uri-encoded", function()
      local res = assert(client:send {
        method = "GET",
        path = "/anytype/test",
        headers = {
          host = "example.com",
        },
      })
      assert.response(res).has.status(200)
    end)
  end)
end
