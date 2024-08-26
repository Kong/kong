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
          api_spec = assert(io.open(helpers.get_fixtures_path() .. "/resources/parameter-serialization-oas.yaml"):read("*a")),
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

    describe("query parameter", function()
      describe("/query", function()
        it("sanity", function()
          local res = assert(client:send {
            method = "GET",
            path = "/query?integer_array=1&integer_array=2&integer_array=3",
            headers = {
              host = "example.com",
            },
          })
          assert.response(res).has.status(200)
        end)
        it("errors", function()
          -- missing required properties
          local res = assert(client:send {
            method = "GET",
            path = "/query",
            headers = {
              host = "example.com",
            },
          })
          assert.response(res).has.status(400)
          local body = assert.response(res).has.jsonbody()
          assert.equal("query 'integer_array' validation failed with error: 'required parameter value not found in request'", body.message)

          -- invalid property type
          local res = assert(client:send {
            method = "GET",
            path = "/query?integer_array=1&integer_array=2&integer_array=str",
            headers = {
              host = "example.com",
            },
          })
          assert.response(res).has.status(400)
          local body = assert.response(res).has.jsonbody()
          assert.equal("query 'integer_array' validation failed with error: 'failed to validate item 3: wrong type: expected integer, got string'", body.message)
        end)
      end)
      describe("/query2", function()
        it("sanity", function()
          local res = assert(client:send {
            method = "GET",
            path = "/query2?required_integer=1&required_string=s",
            headers = {
              host = "example.com",
            },
          })
          assert.response(res).has.status(200)

          local res = assert(client:send {
            method = "GET",
            path = "/query2?required_integer=1&required_string=s&boolean=true",
            headers = {
              host = "example.com",
            },
          })
          assert.response(res).has.status(200)
        end)
        it("errors", function()
          -- missing required properties
          local res = assert(client:send {
            method = "GET",
            path = "/query2?required_string=str",
            headers = {
              host = "example.com",
            },
          })
          assert.response(res).has.status(400)
          local body = assert.response(res).has.jsonbody()
          assert.equal("query 'obj' validation failed with error: 'property required_integer is required'", body.message)

          -- invalid property type
          local res = assert(client:send {
            method = "GET",
            path = "/query2?required_integer=1a&required_string=str",
            headers = {
              host = "example.com",
            },
          })
          assert.response(res).has.status(400)
          local body = assert.response(res).has.jsonbody()
          assert.equal("query 'obj' validation failed with error: 'property required_integer validation failed: wrong type: expected integer, got string'", body.message)
        end)
      end)
      describe("/query/deepObject", function()
        it("sanity", function()
          local res = assert(client:send {
            method = "GET",
            path = "/query/deepObject?deepObject[required_integer]=1&deepObject[required_string]=str",
            headers = {
              host = "example.com",
            },
          })
          assert.response(res).has.status(200)

          local res = assert(client:send {
            method = "GET",
            path = "/query/deepObject?deepObject[required_integer]=1&deepObject[required_string]=str&deepObject[boolean]=true",
            headers = {
              host = "example.com",
            },
          })
          assert.response(res).has.status(200)
        end)
        it("errors", function()
          -- missing required properties
          local res = assert(client:send {
            method = "GET",
            path = "/query/deepObject?deepObject[required_integer]=1",
            headers = {
              host = "example.com",
            },
          })
          assert.response(res).has.status(400)
          local body = assert.response(res).has.jsonbody()
          assert.equal("query 'deepObject' validation failed with error: 'property required_string is required'", body.message)

          -- invalid property type
          local res = assert(client:send {
            method = "GET",
            path = "/query/deepObject?deepObject[required_integer]=1a&deepObject[required_string]=str",
            headers = {
              host = "example.com",
            },
          })
          assert.response(res).has.status(400)
          local body = assert.response(res).has.jsonbody()
          assert.equal("query 'deepObject' validation failed with error: 'property required_integer validation failed: wrong type: expected integer, got string'", body.message)
        end)
      end)
    end)

    describe("path parameter", function()
      describe("/path/object/{simple_object}", function()
        it("sanity", function()
          local res = assert(client:send {
            method = "GET",
            path = "/path/object/required_integer,1,required_string,str",
            headers = {
              host = "example.com",
            },
          })
          assert.response(res).has.status(200)

          local res = assert(client:send {
            method = "GET",
            path = "/path/object/required_integer,1,required_string,str,boolean,true",
            headers = {
              host = "example.com",
            },
          })
          assert.response(res).has.status(200)
        end)
        it("errors", function()
          -- missing required properties
          local res = assert(client:send {
            method = "GET",
            path = "/path/object/required_string,str",
            headers = {
              host = "example.com",
            },
          })
          assert.response(res).has.status(400)
          local body = assert.response(res).has.jsonbody()
          assert.equal("path 'simple_object' validation failed with error: 'property required_integer is required'", body.message)

          -- invalid property type
          local res = assert(client:send {
            method = "GET",
            path = "/path/object/required_integer,1,required_string,str,boolean,1",
            headers = {
              host = "example.com",
            },
          })
          assert.response(res).has.status(400)
          local body = assert.response(res).has.jsonbody()
          assert.equal("path 'simple_object' validation failed with error: 'property boolean validation failed: wrong type: expected boolean, got string'", body.message)
        end)
      end)
      describe("/path/object/{simple_object}/explode", function()
        it("sanity", function()
          local res = assert(client:send {
            method = "GET",
            path = "/path/object/required_integer,1,required_string,str",
            headers = {
              host = "example.com",
            },
          })
          assert.response(res).has.status(200)

          local res = assert(client:send {
            method = "GET",
            path = "/path/object/required_integer=1,required_string=str,boolean=true/explode",
            headers = {
              host = "example.com",
            },
          })
          assert.response(res).has.status(200)
        end)
        it("errors", function()
          -- missing required properties
          local res = assert(client:send {
            method = "GET",
            path = "/path/object/required_string=str/explode",
            headers = {
              host = "example.com",
            },
          })
          assert.response(res).has.status(400)
          local body = assert.response(res).has.jsonbody()
          assert.equal("path 'simple_object' validation failed with error: 'property required_integer is required'", body.message)

          -- invalid property type
          local res = assert(client:send {
            method = "GET",
            path = "/path/object/required_integer=1,required_string=str,boolean=1/explode",
            headers = {
              host = "example.com",
            },
          })
          assert.response(res).has.status(400)
          local body = assert.response(res).has.jsonbody()
          assert.equal("path 'simple_object' validation failed with error: 'property boolean validation failed: wrong type: expected boolean, got string'", body.message)
        end)
      end)
      describe("/path/array/{array}", function()
        it("sanity", function()
          local res = assert(client:send {
            method = "GET",
            path = "/path/array/1",
            headers = {
              host = "example.com",
            },
          })
          assert.response(res).has.status(200)
          local res = assert(client:send {
            method = "GET",
            path = "/path/array/1,2,3",
            headers = {
              host = "example.com",
            },
          })
          assert.response(res).has.status(200)
        end)
        it("errors", function()
          -- invalid iteam type
          local res = assert(client:send {
            method = "GET",
            path = "/path/array/1,2,a",
            headers = {
              host = "example.com",
            },
          })
          assert.response(res).has.status(400)
          local body = assert.response(res).has.jsonbody()
          assert.equal("path 'array' validation failed with error: 'failed to validate item 3: wrong type: expected integer, got string'", body.message)
        end)
      end)
    end)

    describe("header parameter", function()
      describe("/header", function()
        it("sanity", function()
          local res = assert(client:send {
            method = "GET",
            path = "/header",
            headers = {
              integer_array = "1,2,3",
              host = "example.com",
            },
          })
          assert.response(res).has.status(200)

          local res = assert(client:send {
            method = "GET",
            path = "/header",
            headers = {
              obj = "required_integer,1,required_string,str,boolean,true",
              host = "example.com",
            },
          })
          assert.response(res).has.status(200)
        end)
        it("errors", function()
          -- missing required properties
          local res = assert(client:send {
            method = "GET",
            path = "/header",
            headers = {
              obj = "required_integer,1",
              host = "example.com",
            },
          })
          assert.response(res).has.status(400)
          local body = assert.response(res).has.jsonbody()
          assert.equal("header 'obj' validation failed with error: 'property required_string is required'", body.message)

          -- invalid property type
          local res = assert(client:send {
            method = "GET",
            path = "/header",
            headers = {
              integer_array = "1,2,3s",
              host = "example.com",
            },
          })
          assert.response(res).has.status(400)
          local body = assert.response(res).has.jsonbody()
          assert.equal("header 'integer_array' validation failed with error: 'failed to validate item 3: wrong type: expected integer, got string'", body.message)
        end)
      end)
      describe("/header/explode", function()
        it("sanity", function()
          local res = assert(client:send {
            method = "GET",
            path = "/header/explode",
            headers = {
              integer_array = "1,2,3",
              host = "example.com",
            },
          })
          assert.response(res).has.status(200)

          local res = assert(client:send {
            method = "GET",
            path = "/header/explode",
            headers = {
              obj = "required_integer=1,required_string=str,boolean=true",
              host = "example.com",
            },
          })
          assert.response(res).has.status(200)
        end)
        it("errors", function()
          -- missing required properties
          local res = assert(client:send {
            method = "GET",
            path = "/header/explode",
            headers = {
              obj = "required_integer=1",
              host = "example.com",
            },
          })
          assert.response(res).has.status(400)
          local body = assert.response(res).has.jsonbody()
          assert.equal("header 'obj' validation failed with error: 'property required_string is required'", body.message)

          -- invalid property type
          local res = assert(client:send {
            method = "GET",
            path = "/header/explode",
            headers = {
              integer_array = "1,2,3s",
              host = "example.com",
            },
          })
          assert.response(res).has.status(400)
          local body = assert.response(res).has.jsonbody()
          assert.equal("header 'integer_array' validation failed with error: 'failed to validate item 3: wrong type: expected integer, got string'", body.message)
        end)
      end)
    end)
  end)
end
