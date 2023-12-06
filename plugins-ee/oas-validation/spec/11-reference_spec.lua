-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local fixture_path = require("spec.fixtures.fixture_path")
local cjson = require "cjson"

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
        hosts = { "example-swagger.test" },
        service = service1,
      }))
      assert(db.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route1.id },
        config = {
          api_spec = fixture_path.read_fixture("reference-swagger.yaml"),
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
      local route2 = assert(db.routes:insert({
        hosts = { "example-oas.test" },
        service = service1,
      }))
      assert(db.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route2.id },
        config = {
          api_spec = fixture_path.read_fixture("reference-oas.yaml"),
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

    describe("reference", function()
      it("simple case sanity", function()
        for _, host in ipairs({ "example-swagger.test", "example-oas.test" }) do
          local res = assert(client:send {
            method = "POST",
            path = "/ref-case-1",
            headers = {
              host = host,
              ["Content-Type"] = "application/json",
            },
            body = { key_string = "string" }
          })
          assert.response(res).has.status(200)
        end
      end)
      it("simple case fail", function()
        local tests = {
          { host = "example-swagger.test", expected_error = [[{"message":"body 'body' validation failed with error: 'property key_string validation failed: wrong type: expected string, got integer'"}]], },
          { host = "example-oas.test", expected_error = [[{"message":"request body validation failed with error: 'property key_string validation failed: wrong type: expected string, got integer'"}]], },
        }
        for _, test in ipairs(tests) do
          local res = assert(client:send {
            method = "POST",
            path = "/ref-case-1",
            headers = {
              host = test.host,
              ["Content-Type"] = "application/json",
            },
            body = { key_string = 1 }
          })
          local body = assert.res_status(400, res)
          assert.equal(test.expected_error, body)
        end
      end)
      it("array case sanity", function()
        for _, host in ipairs({ "example-swagger.test", "example-oas.test" }) do
          local res = assert(client:send {
            method = "POST",
            path = "/ref-case-2",
            headers = {
              host = host,
              ["Content-Type"] = "application/json",
            },
            body = {
              { key_string = "string"}
            }
          })
          assert.response(res).has.status(200)
        end
      end)
      it("array case fail", function()
        local tests = {
          { host = "example-swagger.test", expected_error = [[{"message":"body 'body' validation failed with error: 'failed to validate item 2: property key_string validation failed: wrong type: expected string, got integer'"}]], },
          { host = "example-oas.test", expected_error = [[{"message":"request body validation failed with error: 'failed to validate item 2: property key_string validation failed: wrong type: expected string, got integer'"}]], },
        }
        for _, test in ipairs(tests) do
          local res = assert(client:send {
            method = "POST",
            path = "/ref-case-2",
            headers = {
              host = test.host,
              ["Content-Type"] = "application/json",
            },
            body = {
              { key_string = "string"},
              { key_string  = 1 }, -- wrong type
            }
          })
          local body = assert.res_status(400, res)
          assert.equal(test.expected_error, body)
        end
      end)
      it("complex case sanity", function()
        for _, host in ipairs({ "example-swagger.test", "example-oas.test" }) do
          local res = assert(client:send {
            method = "POST",
            path = "/ref-case-3",
            headers = {
              host = host,
              ["Content-Type"] = "application/json",
            },
            body = {
              key_integer = 1,
              key_boolean = true,
              simple = { key_string = "string" }
            }
          })
          assert.response(res).has.status(200)
        end
      end)
      it("complex case fail", function()
        local tests = {
          { host = "example-swagger.test", expected_error = [[{"message":"body 'body' validation failed with error: 'property simple validation failed: property key_string validation failed: wrong type: expected string, got integer'"}]], },
          { host = "example-oas.test", expected_error = [[{"message":"request body validation failed with error: 'property simple validation failed: property key_string validation failed: wrong type: expected string, got integer'"}]], },
        }
        for _, test in ipairs(tests) do
          local res = assert(client:send {
            method = "POST",
            path = "/ref-case-3",
            headers = {
              host = test.host,
              ["Content-Type"] = "application/json",
            },
            body = {
              key_integer = 1,
              key_boolean = true,
              simple = { key_string = 1 }
            }
          })
          local body = assert.res_status(400, res)
          assert.equal(test.expected_error, body)
        end
      end)
    end)

    describe("recursive-reference", function()
      it("sanity request", function()
        local sanity_body = {
          differentFields = { "a", "b" },
          securityEligibilityRules = {
            constraint = "constraint1",
            operation = "AND",
            leaves = {
              {
                operation = "AND",
                constraint = "constraint1-1",
                leaves = {
                  {
                    constraint = "constraint1-1-1",
                    operation = "AND"
                  },
                  {
                    constraint = "constraint1-1-2",
                    operation = "AND"
                  }
                }
              },
              {
                operation = "AND",
                constraint = "constraint1-2",
                leaves = {
                  {
                    constraint = "constraint1-2-1",
                    operation = "AND"
                  },
                  {
                    constraint = "constraint1-2-2",
                    operation = "AND"
                  }
                }
              }
            }
          }
        }

        for _, host in ipairs({ "example-swagger.test", "example-oas.test" }) do
          local res = assert(client:send {
            method = "POST",
            path = "/recursive-ref-request-case-1",
            headers = {
              host = host,
              ["Content-Type"] = "application/json",
            },
            body = sanity_body
          })
          assert.response(res).has.status(200)
        end
      end)

      it("sanity response", function()
        local sanity_body = {
          differentFields = { "a", "b" },
          securityEligibilityRules = {
            constraint = "constraint1",
            operation = "AND",
            leaves = {
              {
                operation = "AND",
                constraint = "constraint1-1",
                leaves = {
                  {
                    constraint = "constraint1-1-1",
                    operation = "AND"
                  },
                  {
                    constraint = "constraint1-1-2",
                    operation = "AND"
                  }
                }
              },
              {
                operation = "AND",
                constraint = "constraint1-2",
                leaves = {
                  {
                    constraint = "constraint1-2-1",
                    operation = "AND"
                  },
                  {
                    constraint = "constraint1-2-2",
                    operation = "AND"
                  }
                }
              }
            }
          }
        }
        local json = cjson.encode(sanity_body)

        for _, host in ipairs({ "example-swagger.test", "example-oas.test" }) do
          local res = assert(client:send {
            method = "POST",
            path = "/recursive-ref-response-case-1",
            headers = {
              host = host,
              ["Content-Type"] = "application/json",
              ["X-Mock-Response"] = json
            },
            body = sanity_body
          })
          assert.response(res).has.status(200)
        end
      end)

      it("invalid reqeust with constraint is set to false(bool)", function()
        local invalid_body = {
          differentFields = { "a", "b" },
          securityEligibilityRules = {
            constraint = "constraint1",
            operation = "AND",
            leaves = {
              {
                operation = "AND",
                constraint = "constraint1-1",
                leaves = {
                  {
                    constraint = "constraint1-1-1",
                    operation = "AND"
                  },
                  {
                    constraint = "constraint1-1-2",
                    operation = "AND"
                  }
                }
              },
              {
                operation = "AND",
                constraint = "constraint1-2",
                leaves = {
                  {
                    constraint = "constraint1-2-1",
                    operation = "AND"
                  },
                  {
                    constraint = true, -- wrong type
                    operation = "AND"
                  }
                }
              }
            }
          }
        }

        local tests = {
          { host = "example-swagger.test", expected_error = [[{"message":"body 'body' validation failed with error: 'property securityEligibilityRules validation failed: property leaves validation failed: failed to validate item 2: property leaves validation failed: failed to validate item 2: property constraint validation failed: wrong type: expected string, got boolean'"}]], },
          { host = "example-oas.test", expected_error = [[{"message":"request body validation failed with error: 'property securityEligibilityRules validation failed: property leaves validation failed: failed to validate item 2: property leaves validation failed: failed to validate item 2: property constraint validation failed: wrong type: expected string, got boolean'"}]], },
        }
        for _, test in ipairs(tests) do
          local res = assert(client:send {
            method = "POST",
            path = "/recursive-ref-request-case-1",
            headers = {
              host = test.host,
            },
            body = cjson.encode(invalid_body)
          })
          local body = assert.res_status(400, res)
          assert.equal(test.expected_error, body)
        end
      end)

      it("invalid response with constraint is set to false(bool)", function()
        local invalid_body = {
          differentFields = { "a", "b" },
          securityEligibilityRules = {
            constraint = "constraint1",
            operation = "AND",
            leaves = {
              {
                operation = "AND",
                constraint = "constraint1-1",
                leaves = {
                  {
                    constraint = "constraint1-1-1",
                    operation = "AND"
                  },
                  {
                    constraint = "constraint1-1-2",
                    operation = "AND"
                  }
                }
              },
              {
                operation = "AND",
                constraint = "constraint1-2",
                leaves = {
                  {
                    constraint = "constraint1-2-1",
                    operation = "AND"
                  },
                  {
                    constraint = true, -- wrong type
                    operation = "AND"
                  }
                }
              }
            }
          }
        }
        local json = cjson.encode(invalid_body)

        for _, host in ipairs({ "example-swagger.test", "example-oas.test" }) do
          local res = assert(client:send {
            method = "POST",
            path = "/recursive-ref-response-case-1",
            headers = {
              host = host,
              ["X-Mock-Response"] = json
            },
          })
          local body = assert.res_status(406, res)
          assert.equal(
            [[{"message":"response body validation failed with error: property securityEligibilityRules validation failed: property leaves validation failed: failed to validate item 2: property leaves validation failed: failed to validate item 2: property constraint validation failed: wrong type: expected string, got boolean"}]],
            body
          )
        end
      end)
    end)
  end)
end
