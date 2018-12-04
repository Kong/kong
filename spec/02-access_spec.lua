local helpers = require "spec.helpers"
local cjson = require "cjson"


local test_plugin_id
local function add_plugin(admin_client, config, expected_status)
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

for _, strategy in helpers.each_strategy("postgres") do
  local proxy_client
  local admin_client

  describe("Plugin: request-validator (access) [#" .. strategy .. "]", function()
    setup(function()
      local bp = helpers.get_db_utils(strategy)

      bp.routes:insert {
        paths = {"/"}
      }

      assert(helpers.start_kong({
        nginx_conf = "spec/fixtures/custom_nginx.template",
        database = strategy,
        custom_plugins = "request-validator",
      }))
      proxy_client = helpers.proxy_client()
      admin_client = helpers.admin_client()
    end)

    teardown(function()
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
        [
          {
            "f": {}
          }
        ]
      ]],
      [[
        [
          {
            "f": {
              "type": "string",
              "foo_bar": ""
            }
          }
        ]
      ]]
    }

    describe("request-validator", function()
      for _, schema in ipairs(invalid_schema_jsons) do
        it("errors with invalid schema json", function()
          local plugin = add_plugin(admin_client, {body_schema = schema}, 400)
          assert.same("failed decoding schema", plugin.config)
        end)
      end

      for _, schema in ipairs(invalid_schemas) do
        it("errors with invalid schemas", function()
          local plugin = add_plugin(admin_client, {body_schema = schema}, 400)
          assert.match("^.*schema violation.*$", plugin.config)
        end)
      end

      it("validates empty body with empty schema", function()
        add_plugin(admin_client, {body_schema = '[]'}, 201)
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

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Content-Type"] = "application/json",
          },
          body = {
            field = "value",
          }
        })
        local json = cjson.decode(assert.res_status(400, res))
        assert.same("request body doesn't conform to schema", json.message)
      end)

      it("validates simple key-value body", function()
        local schema = [[
          [
            {
              "f1": {
                "type": "string",
                "required": true
              }
            }
          ]
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
          [
            {
              "f1": {
                "type": "string",
                "required": true
              }
            },
            {
              "r1": {
                "type": "record",
                "required": true,
                "fields": [
                  {
                    "rf1": {
                      "type": "boolean",
                      "required": true
                    }
                  }
                ]
              }
            }
          ]
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

      it("validates arrays", function()
        local schema = [[
          [
            {
              "a": {
                "type": "array",
                "required": true,
                "elements": {
                  "type": "integer"
                }
              }
            }
          ]
        ]]
        add_plugin(admin_client, {body_schema = schema}, 201)

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Content-Type"] = "application/json",
          },
          body = {
            a = {1, 2, 3, 4}
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
            a = {"string"}
          }
        })
        local json = cjson.decode(assert.res_status(400, res))
        assert.same("request body doesn't conform to schema", json.message)
      end)

      it("validates maps", function()
        local schema = [[
          [
            {
              "m": {
                "type": "map",
                "required": true,
                "keys": {
                  "type": "string"
                },
                "values": {
                  "type": "boolean"
                }
              }
            }
          ]
        ]]
        add_plugin(admin_client, {body_schema = schema}, 201)

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Content-Type"] = "application/json",
          },
          body = {
            m = {
              s1 = false,
              s2 = true
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
            m = {
              s1 = "bar",
              s2 = "foo"
            }
          }
        })
        local json = cjson.decode(assert.res_status(400, res))
        assert.same("request body doesn't conform to schema", json.message)
      end)

      it("accepts validators", function()
        local schema = [[
          [
            {
              "f1": {
                "type": "integer",
                "required": true,
                "between": [1, 10]
              }
            },
            {
              "f2": {
                "type": "string",
                "required": true,
                "match": "^abc$"
              }
            }
          ]
        ]]
        add_plugin(admin_client, {body_schema = schema}, 201)

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Content-Type"] = "application/json",
          },
          body = {
            f1 = 5,
            f2 = "abc"
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
            f1 = 15,
            f2 = "abc"
          }
        })
        local json = cjson.decode(assert.res_status(400, res))
        assert.same("request body doesn't conform to schema", json.message)

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Content-Type"] = "application/json",
          },
          body = {
            f1 = 5,
            f2 = "bca"
          }
        })
        local json = cjson.decode(assert.res_status(400, res))
        assert.same("request body doesn't conform to schema", json.message)
      end)
    end)
  end)
end
