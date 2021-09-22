-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson"

local strategies = helpers.all_strategies ~= nil and helpers.all_strategies or helpers.each_strategy

local test_plugin_id
local function add_plugin(admin_client, config, expected_status)
  config.version = "draft4"
  local res = assert(admin_client:send {
    method = "POST",
    path = "/plugins",
    headers = {
      ["Content-Type"] = "application/json"
    },
    body = {
      name = "request-validator",
      config = config,
    }
  })

  assert.response(res).has.status(expected_status)
  local json = assert.response(res).has.jsonbody()
  test_plugin_id = json.id
  return json
end

for _, strategy in strategies() do
  local proxy_client
  local admin_client
  local db_strategy = strategy ~= "off" and strategy or nil

  describe("Plugin: request-validator (access) [#" .. strategy .. "]", function()
    lazy_setup(function()
      local bp = helpers.get_db_utils(db_strategy, nil, { "request-validator" })

      bp.routes:insert {
        paths = {"/"}
      }

      assert(helpers.start_kong({
        nginx_conf = "spec/fixtures/custom_nginx.template",
        database = db_strategy,
        plugins = "request-validator",
      }))

      proxy_client = helpers.proxy_client()
      admin_client = helpers.admin_client()
    end)

    lazy_teardown(function()
      if proxy_client then
        proxy_client:close()
      end
      if admin_client then
        admin_client:close()
      end
      helpers.stop_kong()
    end)

    after_each(function()
      -- when a test plugin was added, we remove it again to clean up
      if test_plugin_id then
        local res = assert(admin_client:send {
          method = "DELETE",
          path = "/plugins/" .. test_plugin_id,
        })
        assert.response(res).has.status(204)
      end
      test_plugin_id = nil
    end)

    local invalid_schema_jsons = {
      [[
        [
        }
      ]],
      [[
        "f": {}
      ]],
      [[
        [
          "f": "string"
        ]
      ]],
    }

    local invalid_schemas = {
      [[
        {
            "type": 123,
            "definitions": { "err": "type should have been string" }
        }
      ]],
      [[
        {
            "type": "object",
            "definitions": [ "should have been an object" ]
        }
      ]]
    }

    describe("[draft4]", function()
      for _, schema in ipairs(invalid_schema_jsons) do
        it("errors with invalid schema json", function()
          local plugin = add_plugin(admin_client, {body_schema = schema}, 400)
          assert.same("failed decoding schema: ", plugin.fields["@entity"][1]:sub(1,24))
        end)
      end

      for _, schema in ipairs(invalid_schemas) do
        it("errors with invalid schemas", function()
          local plugin = add_plugin(admin_client, {body_schema = schema}, 400)
          assert.same("not a valid JSONschema draft 4 schema:", plugin.fields["@entity"][1]:sub(1, 38))
        end)
      end

      it("validates empty body with empty schema", function()
        add_plugin(admin_client, {body_schema = '{}'}, 201)
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Content-Type"] = "application/json",
          },
          body = {
          }
        })
        assert.res_status(200, res)
      end)

      it("validates simple key-value body", function()
        local schema = [[
            {
              "properties": {
                "f1": {
                  "type": "string"
                }
              },
              "required": [ "f1" ]
            }
        ]]
        add_plugin(admin_client, {body_schema = schema}, 201)

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Content-Type"] = "application/json",
          },
          body = {
            f1 = "value!"
          }
        })
        assert.res_status(200, res)

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Content-Type"] = "application/json",
          },
          body = {
          }
        })
        local json = cjson.decode(assert.res_status(400, res))
        assert.same("request body doesn't conform to schema", json.message)
      end)

      it("validates nested records", function()
        local schema = [[
            {
              "properties": {
                "f1": {
                  "type": "string"
                },
                "r1" : {
                  "type": "object",
                  "properties": {
                    "rf1": {
                      "type": "boolean"
                    }
                  },
                  "required": [ "rf1" ]
                }
              },
              "required": [ "f1", "r1" ]
            }
        ]]
        add_plugin(admin_client, {body_schema = schema}, 201)

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Content-Type"] = "application/json",
          },
          body = {
            f1 = "value!",
            r1 = {
              rf1 = false,
            }
          }
        })
        assert.res_status(200, res)

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Content-Type"] = "application/json",
          },
          body = {
            f1 = "value"
          }
        })
        local json = cjson.decode(assert.res_status(400, res))
        assert.same("request body doesn't conform to schema", json.message)
      end)



      describe("simple JSON", function()

        it("validates plain boolean", function()
          local schema = [[ { "type": "boolean" } ]]
          add_plugin(admin_client, {body_schema = schema}, 201)

          local res = proxy_client:get("/status/200", {
            headers = { ["Content-Type"] = "application/json" },
            body = "true"
          })
          assert.response(res).has.status(200)

          local res = proxy_client:get("/status/200", {
            headers = { ["Content-Type"] = "application/json" },
            body = '"a string value"'
          })
          assert.response(res).has.status(400)
        end)


        it("validates plain string", function()
          local schema = [[ { "type": "string" } ]]
          add_plugin(admin_client, {body_schema = schema}, 201)

          local res = proxy_client:get("/status/200", {
            headers = { ["Content-Type"] = "application/json" },
            body = '"hello world"'
          })
          assert.response(res).has.status(200)

          local res = proxy_client:get("/status/200", {
            headers = { ["Content-Type"] = "application/json" },
            body = "true"
          })
          assert.response(res).has.status(400)
        end)


        it("validates plain number", function()
          local schema = [[ { "type": "number" } ]]
          add_plugin(admin_client, {body_schema = schema}, 201)

          local res = proxy_client:get("/status/200", {
            headers = { ["Content-Type"] = "application/json" },
            body = '123'
          })
          assert.response(res).has.status(200)

          local res = proxy_client:get("/status/200", {
            headers = { ["Content-Type"] = "application/json" },
            body = "true"
          })
          assert.response(res).has.status(400)
        end)


        it("allows anything", function()
          local schema = [[ {} ]]
          add_plugin(admin_client, {body_schema = schema}, 201)

          -- string
          local res = proxy_client:get("/status/200", {
            headers = { ["Content-Type"] = "application/json" },
            body = '"hello world"'
          })
          assert.response(res).has.status(200)

          -- boolean
          local res = proxy_client:get("/status/200", {
            headers = { ["Content-Type"] = "application/json" },
            body = 'true'
          })
          assert.response(res).has.status(200)

          -- number
          local res = proxy_client:get("/status/200", {
            headers = { ["Content-Type"] = "application/json" },
            body = '123'
          })
          assert.response(res).has.status(200)

          -- object
          local res = proxy_client:get("/status/200", {
            headers = { ["Content-Type"] = "application/json" },
            body = '{ "hello": "world" }'
          })
          assert.response(res).has.status(200)

          -- array
          local res = proxy_client:get("/status/200", {
            headers = { ["Content-Type"] = "application/json" },
            body = '[ "hello", "world" ]'
          })
          assert.response(res).has.status(200)
        end)

      end)



      it("validates parameters with version draft4", function()
        local schema = [[
            {
              "properties": {
                "f1": {
                  "type": "string"
                },
                "r1" : {
                  "type": "object",
                  "properties": {
                    "rf1": {
                      "type": "boolean"
                    }
                  },
                  "required": [ "rf1" ]
                }
              },
              "required": [ "f1", "r1" ]
            }
        ]]

        local param_schema = {
          {
            name = "x-kong-name",
            ["in"] = "header",
            required = true,
            schema = '{"type": "array", "items": {"type": "integer"}}',
            style = "simple",
            explode = false,
          }
        }

        add_plugin(admin_client, {body_schema = schema, parameter_schema = param_schema}, 201)

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Content-Type"] = "application/json",
            ["x-kong-name"] = "1,2,3",
          },
          body = {
            f1 = "value!",
            r1 = {
              rf1 = false,
            }
          }
        })
        assert.res_status(200, res)

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Content-Type"] = "application/json",
            ["x-kong-name"] = "a,b,c",
          },
          body = {
            f1 = "abc"
          }
        })
        assert.res_status(400, res)
      end)

      it("verbose response for body schema validation", function()
        local body_schema = [[
            {
              "properties": {
                "f1": {
                  "type": "string"
                },
                "arr" : {
                  "type": "array",
                  "items": {
                    "type": "string"
                  }
                }
              },
              "required": [ "f1", "arr" ]
            }
        ]]

        add_plugin(admin_client, {body_schema = body_schema, verbose_response = true }, 201)

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/anything",
          headers = {
            ["Content-Type"] = "application/json",
            ["Host"] = "path.com",
          },
          body = {
            f1 = true,
            arr = {
              "a",
              "b"
            }
          }
        })
        local json = cjson.decode(assert.res_status(400, res))
        assert.same("property f1 validation failed: wrong type: expected string, got boolean", json.message)

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/anything",
          headers = {
            ["Content-Type"] = "application/json",
            ["Host"] = "path.com",
          },
          body = {
            f1 = "value",
            arr = {
              true,
            }
          }
        })
        local json = cjson.decode(assert.res_status(400, res))
        assert.same("property arr validation failed: failed to validate item 1: wrong type: expected string, got boolean", json.message)
      end)


      it("verbose response for parameter schema validation, required and provided", function()
        local body_schema = [[
            {
              "properties": {
                "f1": {
                  "type": "string"
                }
               }
            }
        ]]

        local param_schema = {
          {
            name = "x-kong-name",
            ["in"] = "header",
            required = true,
            schema = '{"type": "array", "items": {"type": "integer"}}',
            style = "simple",
            explode = false,
          }
        }

        add_plugin(admin_client, {body_schema = body_schema, parameter_schema = param_schema, verbose_response = true }, 201)

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Content-Type"] = "application/json",
            ["x-kong-name"] = "a,b,c",
          },
          body = {
            f1 = "abc"
          }
        })
        assert.response(res).has.status(400)
        local json = assert.response(res).has.jsonbody()
        assert.same({
          message = "header 'x-kong-name' validation failed, [error] failed to validate item 1: wrong type: expected integer, got string",
          data = { "a", "b", "c" }
        }, json)
      end)


      it("verbose response for parameter schema validation, required but not provided", function()
        local body_schema = [[
            {
              "properties": {
                "f1": {
                  "type": "string"
                }
               }
            }
        ]]

        local param_schema = {
          {
            name = "x-kong-name",
            ["in"] = "header",
            required = true,
            schema = '{"type": "array", "items": {"type": "integer"}}',
            style = "simple",
            explode = false,
          }
        }

        add_plugin(admin_client, {body_schema = body_schema, parameter_schema = param_schema, verbose_response = true }, 201)

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Content-Type"] = "application/json",
            --["x-kong-name"] = "a,b,c",         -- do not provide the required header
          },
          body = {
            f1 = "abc"
          }
        })
        assert.response(res).has.status(400)
        local json = assert.response(res).has.jsonbody()
        assert.same({
          message = "header 'x-kong-name' validation failed, [error] required parameter missing"
        }, json)
      end)


      it("parameter type[object] validation for multi/single header with a object(delim: =) value #explode -> true", function()
        local param_schema = {
          {
            name = "x-kong-name",
            ["in"] = "header",
            required = true,
            schema = '{"type": "object"}',
            style = "simple",
            explode = true,
          }
        }
        add_plugin(admin_client, {parameter_schema = param_schema, verbose_response = true }, 201)

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Content-Type"] = "application/json",
            ["x-kong-name"] = "role=admin,firstName=Alex",
          },
          body = { }
        })
        assert.response(res).has.status(200)
        assert.response(res).has.jsonbody()

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Content-Type"] = "application/json",
            ["x-kong-name"] = "role=admin,firstName=Alex",
          },
          body = { }
        })
        assert.response(res).has.status(200)
        assert.response(res).has.jsonbody()
      end)

      it("parameter type[object] validation for multi/single headers with a object(delim: ,) value #explode -> false", function()
        local param_schema = {
          {
            name = "x-kong-name",
            ["in"] = "header",
            required = true,
            schema = '{"type": "object"}',
            style = "simple",
            explode = false,
          }
        }
        add_plugin(admin_client, {parameter_schema = param_schema, verbose_response = true }, 201)

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Content-Type"] = "application/json",
            ["x-kong-name"] = "role,admin,firstName,Alex",
          },
          body = { }
        })
        assert.response(res).has.status(200)
        assert.response(res).has.jsonbody()

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Content-Type"] = "application/json",
            ["x-kong-name"] = "role,admin,firstName,Alex",
          },
          body = { }
        })
        assert.response(res).has.status(200)
        assert.response(res).has.jsonbody()
      end)

      for _, explode in ipairs({true, false}) do
      -- behavior for explode->true & explode->false are identical

          local param_schema = {
            {
              name = "x-kong-name",
              ["in"] = "header",
              required = true,
              schema = '{"type": "string"}',
              style = "simple",
              explode = explode,
            }
          }

        it("parameter type[primitive] validation for single header with a primitive value #explode -> " .. tostring(explode), function()
          add_plugin(admin_client, {parameter_schema = param_schema, verbose_response = true }, 201)

          local res = assert(proxy_client:send {
            method = "GET",
            path = "/status/200",
            headers = {
              ["Content-Type"] = "application/json",
              ["x-kong-name"] = "a",
            },
            body = { }
          })
          assert.response(res).has.status(200)
          assert.response(res).has.jsonbody()
        end)
      end

      for _, explode in ipairs({true, false}) do
      -- behavior for explode->true & explode->false are identical

          local param_schema = {
            {
              name = "kong-name",
              ["in"] = "header",
              required = true,
              schema = '{"type": "array", "items": {"type": "string"}}',
              style = "simple",
              explode = explode,
            }
          }

        it("parameter type[simple] validation for single header with comma separated values #explode -> " .. tostring(explode), function()
          add_plugin(admin_client, {parameter_schema = param_schema, verbose_response = true }, 201)

          local res = assert(proxy_client:send {
            method = "GET",
            path = "/status/200",
            headers = {
              ["Content-Type"] = "application/json",
              ["kong-name"] = "a,b,c",
            },
            body = { }
          })
          assert.response(res).has.status(200)
          assert.response(res).has.jsonbody()
        end)

        it("parameter type[simple] validation for single headers without csvs with #explode -> " .. tostring(explode), function()
          add_plugin(admin_client, {parameter_schema = param_schema, verbose_response = true }, 201)
          local res = assert(proxy_client:send {
            method = "GET",
            path = "/status/200",
            headers = {
              ["Content-Type"] = "application/json",
              ["kong-name"] = "a",
            },
            body = { }
          })
          assert.response(res).has.status(400)
          local json = assert.response(res).has.jsonbody()
          assert.same("header 'kong-name' validation failed, [error] wrong type: expected array, got string", json.message)
        end)
      end
    end)
  end)
end
