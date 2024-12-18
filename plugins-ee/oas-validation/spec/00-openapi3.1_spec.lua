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
          api_spec = assert(io.open(helpers.get_fixtures_path() .. "/resources/openapi_3.1.yaml"):read("*a")),
          validate_response_body = true,
          validate_request_header_params = true,
          validate_request_query_params = true,
          validate_request_uri_params = true,
          header_parameter_check = false,
          query_parameter_check = true,
          verbose_response = true,
          api_spec_encoded = false,
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

    describe("type can be array", function()
      it("property is nullable", function()
        local res = assert(client:send {
          method = "POST",
          path = "/feature/array-type",
          headers = {
            host = "example.com",
            ["content-type"] = "application/json",
          },
          body = {
            integer_nullable = 1,
          }
        })
        assert.response(res).has.status(200)

        local res = assert(client:send {
          method = "POST",
          path = "/feature/array-type",
          headers = {
            host = "example.com",
            ["content-type"] = "application/json",
          },
          body = {
            integer_nullable = nil,
          }
        })
        assert.response(res).has.status(200)
      end)
      it("property can be multiple types", function()
        local res = assert(client:send {
          method = "POST",
          path = "/feature/array-type",
          headers = {
            host = "example.com",
            ["content-type"] = "application/json",
          },
          body = {
            integer_string = 1,
          }
        })
        assert.response(res).has.status(200)

        local res = assert(client:send {
          method = "POST",
          path = "/feature/array-type",
          headers = {
            host = "example.com",
            ["content-type"] = "application/json",
          },
          body = {
            integer_string = "1",
          }
        })
        assert.response(res).has.status(200)
      end)
    end)

    describe("type can be omitted", function()
      it("optional type", function()
        local accepted_values = {
          '{"arbitrary_value": null}',
          '{"arbitrary_value": 1}',
          '{"arbitrary_value": "1"}',
          '{"arbitrary_value": true}',
          '{"arbitrary_value": { "key": "value" }}',
          '{"arbitrary_value": [ "1", "2", "3" ]}',
        }
        for _, json in ipairs(accepted_values) do
          local res = assert(client:send {
            method = "POST",
            path = "/feature/optional-type",
            headers = {
              host = "example.com",
            },
            body = json
          })
          assert.response(res).has.status(200)
        end

      end)
    end)

    describe("format", function()
      it("sanity", function()
        local res = assert(client:send {
          method = "POST",
          path = "/feature/format",
          headers = {
            host = "example.com",
            ["content-type"] = "application/json",
          },
          body = {
            ipv4 = "127.0.0.1",
            ipv6 = "2001:0db8:85a3:0000:0000:8a2e:0370:7334",
            uuid = "00000000-0000-0000-0000-000000000000",
            hostname = "www.example.com",
          }
        })
        assert.response(res).has.status(200)
      end)
      it("rejects invalid ipv4", function()
        local res = assert(client:send {
          method = "POST",
          path = "/feature/format",
          headers = {
            host = "example.com",
            ["content-type"] = "application/json",
          },
          body = {
            ipv4 = "127.0.0",
          }
        })
        assert.response(res).has.status(400)
        local body = assert.response(res).has.jsonbody()
        assert.equal(
          [[request body validation failed with error: 'input does not conforms to the provided schema, ["127.0.0" is not a "ipv4", /ipv4]']],
          body.message)
      end)
      it("rejects invalid ipv6", function()
        local res = assert(client:send {
          method = "POST",
          path = "/feature/format",
          headers = {
            host = "example.com",
            ["content-type"] = "application/json",
          },
          body = {
            ipv6 = "2001:0db8:85a3:0000:0000",
          }
        })
        assert.response(res).has.status(400)
        local body = assert.response(res).has.jsonbody()
        assert.equal(
          [[request body validation failed with error: 'input does not conforms to the provided schema, ["2001:0db8:85a3:0000:0000" is not a "ipv6", /ipv6]']],
          body.message)
      end)
    end)

    describe("schema contains arbitrary keywords", function()
      it("works as normal when schema contains arbitrary keywords", function()
        local res = assert(client:send {
          method = "POST",
          path = "/feature/arbitrary-keywords",
          headers = {
            host = "example.com",
            ["content-type"] = "application/json",
          },
          body = {}
        })
        -- should works as normal when schema contains arbitrary keywords (not-matter-what: "value")
        assert.response(res).has.status(200)
      end)
    end)

    describe("regex", function()
      it("accepts utf-8 characters", function()
        local q = ngx.escape_uri("azAZаяАЯІіЇїЄєҐґ09+-!ʼ',/()\t.%")
        local res = assert(client:send {
          method = "GET",
          path = "/regex/utf-8?q=" .. q,
          headers = {
            host = "example.com",
          },
        })
        assert.response(res).has.status(200)
      end)
    end)

    describe("parameter", function()
      it("sanity", function()
        local res = assert(client:send {
          method = "GET",
          path = "/parameter/query?integer=1&boolean=true&string=str&number=1.23",
          headers = {
            host = "example.com",
          },
        })
        assert.response(res).has.status(200)
      end)

      it("accepts boolean params without value", function ()
        local res = assert(client:send {
          method = "GET",
          path = "/parameter/query?integer=1&boolean&string=str&number=1.23",
          headers = {
            host = "example.com",
          },
        })
        assert.response(res).has.status(200)
      end)

      it("invalid type", function()
        local res = assert(client:send {
          method = "GET",
          path = "/parameter/query?integer=1s",
          headers = {
            host = "example.com",
          },
        })
        assert.response(res).has.status(400)
        local body = assert.response(res).has.jsonbody()
        assert.equal(
          [[query 'integer' validation failed with error: 'failed to parse '1s' from string to integer']],
          body.message)
      end)

      it("rejects boolean params with empty string value", function()
        local res = assert(client:send {
          method = "GET",
          path = "/parameter/query?integer=1&boolean=&string=str&number=1.23",
          headers = {
            host = "example.com",
          },
        })
        assert.response(res).has.status(400)
        local body = assert.response(res).has.jsonbody()
        assert.equal(
          [[query 'boolean' validation failed with error: 'failed to parse '' from string to boolean']],
          body.message)
      end)
    end)
  end)
end
