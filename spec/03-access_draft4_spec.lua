local helpers = require "spec.helpers"
local cjson = require "cjson"


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

for _, strategy in helpers.each_strategy()do
  local proxy_client
  local admin_client

  describe("Plugin: request-validator (access) [#" .. strategy .. "]", function()
    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, nil, { "request-validator" })

      bp.routes:insert {
        paths = {"/"}
      }

      assert(helpers.start_kong({
        nginx_conf = "spec/fixtures/custom_nginx.template",
        database = strategy,
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

    end)
  end)
end
