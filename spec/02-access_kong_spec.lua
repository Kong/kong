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

for _, strategy in helpers.each_strategy()do
  local proxy_client
  local admin_client

  describe("Plugin: request-validator (access) [#" .. strategy .. "]", function()
    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, nil, { "request-validator" })

      bp.routes:insert {
        paths = {"/"}
      }

      bp.routes:insert {
        paths = {"/resources/(?<resource_id>\\S+)/"},
        hosts = {"path.com"}
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
      helpers.stop_kong(nil, true)
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

    describe("[kong]", function()
      for _, schema in ipairs(invalid_schema_jsons) do
        it("errors with invalid schema json", function()
          local plugin = add_plugin(admin_client, {body_schema = schema}, 400)
          assert.same("failed decoding schema: ", plugin.fields["@entity"][1]:sub(1,24))
        end)
      end

      for _, schema in ipairs(invalid_schemas) do
        it("errors with invalid schemas", function()
          local plugin = add_plugin(admin_client, {body_schema = schema}, 400)
          assert.same("schema violation", plugin.fields["@entity"][1].name)
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

      it("allow supported content-type", function()
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

        add_plugin(admin_client, {body_schema = schema, allowed_content_types = {
          "application/xml",
          "application/json",
        }}, 201)

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
            ["Content-Type"] = "application/xml",
          },
          body = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
        })
        assert.res_status(200, res)
      end)

      it("allow default content-type", function()
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

        add_plugin(admin_client, {body_schema = schema }, 201)

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
            ["Content-Type"] = "application/xml",
          },
          body = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
        })
        assert.res_status(400, res)
      end)

      it("block non supported content-type", function()
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

        add_plugin(admin_client, {body_schema = schema, allowed_content_types = {
          "application/json",
        }}, 201)

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
            ["Content-Type"] = "application/xml",
          },
          body = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
        })
        assert.res_status(400, res)
      end)

      it("allows type-wildcard content-type", function()
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

        add_plugin(admin_client, {body_schema = schema, allowed_content_types = {
          "*/json",
        } }, 201)

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Content-Type"] = "something/json",
          },
          body = cjson.encode({
            f1 = true, -- non-validated
          })
        })
        assert.res_status(200, res)

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Content-Type"] = "application/xml",
          },
          body = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
        })
        assert.res_status(400, res)
      end)

      it("allows subtype-wildcard content-type", function()
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

        add_plugin(admin_client, {body_schema = schema, allowed_content_types = {
          "application/*",
        } }, 201)

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
            ["Content-Type"] = "application/xml",
          },
          body = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
        })
        assert.res_status(200, res)
      end)

      it("allows */* content-type", function()
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

        add_plugin(admin_client, {body_schema = schema, allowed_content_types = {
          "*/*",
        } }, 201)

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
            --["Content-Type"] = "application/xml",  -- no header is NOT allowed
          },
          body = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
        })
        assert.res_status(400, res)
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

      it("location: header, style: simple, explode:false schema_type: array items_type: integer", function()
        local body_schema = [[
          [
            {
              "f1": {
                "type": "string"
              }
            }
          ]
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

        add_plugin(admin_client, {body_schema = body_schema, parameter_schema = param_schema}, 201)

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Content-Type"] = "application/json",
            ["x-kong-name"] = "1,2,3",
          },
          body = {
            f1 = "abc"
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

      it("location: header, style: simple, explode:false schema_type: array items_type: integer header: nil", function()
        local body_schema = [[
          [
            {
              "f1": {
                "type": "string"
              }
            }
          ]
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

        add_plugin(admin_client, {body_schema = body_schema, parameter_schema = param_schema}, 201)

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Content-Type"] = "application/json",
          },
          body = {
            f1 = "abc"
          }
        })
        assert.res_status(400, res)
      end)

      it("location: header, style: simple, explode:false schema_type: array items_type: integer header: nil", function()
        local body_schema = [[
          [
            {
              "f1": {
                "type": "string"
              }
            }
          ]
        ]]

        local param_schema = {
          {
            name = "x-kong-name",
            ["in"] = "header",
            required = false,
            schema = '{"type": "array", "items": {"type": "integer"}}',
            style = "simple",
            explode = false,
          }
        }

        add_plugin(admin_client, {body_schema = body_schema, parameter_schema = param_schema}, 201)

        -- allow when header not set
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Content-Type"] = "application/json",
          },
          body = {
            f1 = "abc"
          }
        })
        assert.res_status(200, res)

        -- allow when header set matching schema
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Content-Type"] = "application/json",
            ["x-kong-name"] = "1,2,3",
          },
          body = {
            f1 = "abc"
          }
        })
        assert.res_status(200, res)

        -- not allow when header set not matching schema
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

      it("location: header, style: simple, explode:true schema_type: array items_type: string", function()
        local body_schema = [[
          [
            {
              "f1": {
                "type": "string"
              }
            }
          ]
        ]]

        local param_schema = {
          {
            name = "x-kong-name",
            ["in"] = "header",
            required = true,
            schema = '{"type": "array", "items": {"type": "string"}}',
            style = "simple",
            explode = true,
          }
        }


        add_plugin(admin_client, {body_schema = body_schema, parameter_schema = param_schema}, 201)

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
        assert.res_status(200, res)
      end)

      it("location: header, style: simple, explode:false schema_type: object items_type: string", function()
        local body_schema = [[
          [
            {
              "f1": {
                "type": "string"
              }
            }
          ]
        ]]

        local param_schema = {
          {
            name = "x-kong-name",
            ["in"] = "header",
            required = true,
            schema = [[
           {
              "type": "object",
              "required": ["a", "b"],
              "properties": {
                "a": {
                  "type": "string"
                },
                "b": {
                  "type": "string"
                }
              }
            }]],
            style = "simple",
            explode = false,
          }
        }

        add_plugin(admin_client, {body_schema = body_schema, parameter_schema = param_schema}, 201)

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Content-Type"] = "application/json",
            ["x-kong-name"] = "a,val_a,b,val_b",
          },
          body = {
            f1 = "abc"
          }
        })
        assert.res_status(200, res)

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Content-Type"] = "application/json",
            ["x-kong-name"] = "a=val_a,b=val_b",
          },
          body = {
            f1 = "abc"
          }
        })
        assert.res_status(400, res)
      end)

      it("location: header, style: simple, explode:true schema_type: object items_type: string", function()
        local body_schema = [[
          [
            {
              "f1": {
                "type": "string"
              }
            }
          ]
        ]]

        local param_schema = {
          {
            name = "x-kong-name",
            ["in"] = "header",
            required = true,
            schema = [[
            {
              "type": "object",
              "required": ["a", "b"],
              "properties": {
                "a": {
                  "type": "string"
                },
                "b": {
                  "type": "string"
                }
              }
            }]],
            style = "simple",
            explode = true,
          }
        }

        add_plugin(admin_client, {body_schema = body_schema, parameter_schema = param_schema}, 201)

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Content-Type"] = "application/json",
            ["x-kong-name"] = "a=val_a,b=val_b",
          },
          body = {
            f1 = "abc"
          }
        })
        assert.res_status(200, res)

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Content-Type"] = "application/json",
            ["x-kong-name"] = "a,val_a,b,val_b",
          },
          body = {
            f1 = "abc"
          }
        })
        assert.res_status(400, res)
      end)

      it("location: path, style: simple, explode:true schema_type:string", function()
        local body_schema = [[
          [
            {
              "f1": {
                "type": "string"
              }
            }
          ]
        ]]

        local param_schema = {
          {
            name = "resource_id",
            ["in"] = "path",
            required = true,
            schema = '{"type": "string"}',
            style = "simple",
            explode = true,
          }
        }

        add_plugin(admin_client, {body_schema = body_schema, parameter_schema = param_schema}, 201)

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/resources/200/anything",
          headers = {
            ["Content-Type"] = "application/json",
            ["Host"] = "path.com",
          },
          body = {
            f1 = "abc"
          }
        })
        assert.res_status(200, res)

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/resources/",
          headers = {
            ["Content-Type"] = "application/json",
            ["Host"] = "path.com",
          },
          body = {
            f1 = "abc"
          }
        })
        assert.res_status(400, res)
      end)

      it("location: path, style: label, explode:true schema_type: string", function()
        local body_schema = [[
          [
            {
              "f1": {
                "type": "string"
              }
            }
          ]
        ]]

        local param_schema = {
          {
            name = "resource_id",
            ["in"] = "path",
            required = true,
            schema = '{"type": "string"}',
            style = "simple",
            explode = true,
          }
        }

        add_plugin(admin_client, {body_schema = body_schema, parameter_schema = param_schema}, 201)

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/resources/.200/anything",
          headers = {
            ["Content-Type"] = "application/json",
            ["Host"] = "path.com",
          },
          body = {
            f1 = "abc"
          }
        })
        assert.res_status(200, res)

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/resources/",
          headers = {
            ["Content-Type"] = "application/json",
            ["Host"] = "path.com",
          },
          body = {
            f1 = "abc"
          }
        })
        assert.res_status(400, res)
      end)

      it("location: path, style: label, explode:true schema_type: array item_type: integer", function()
        local body_schema = [[
          [
            {
              "f1": {
                "type": "string"
              }
            }
          ]
        ]]

        local param_schema = {
          {
            name = "resource_id",
            ["in"] = "path",
            required = true,
            schema = '{"type": "array", "items": {"type": "integer"}}',
            style = "label",
            explode = true,
          }
        }


        add_plugin(admin_client, {body_schema = body_schema, parameter_schema = param_schema}, 201)

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/resources/.1.2.3/anything",
          headers = {
            ["Content-Type"] = "application/json",
            ["Host"] = "path.com",
          },
          body = {
            f1 = "abc"
          }
        })
        assert.res_status(200, res)

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/resources/.1,2,3/anything",
          headers = {
            ["Content-Type"] = "application/json",
            ["Host"] = "path.com",
          },
          body = {
            f1 = "abc"
          }
        })
        assert.res_status(400, res)

      end)

      it("location: path, style: label, explode:false schema_type: array item_type: string", function()
        local body_schema = [[
          [
            {
              "f1": {
                "type": "string"
              }
            }
          ]
        ]]

        local param_schema = {
          {
            name = "resource_id",
            ["in"] = "path",
            required = true,
            schema = '{"type": "array", "items": {"type": "integer"}}',
            style = "label",
            explode = false,
          }
        }


        add_plugin(admin_client, {body_schema = body_schema, parameter_schema = param_schema}, 201)

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/resources/.1,2,3/anything",
          headers = {
            ["Content-Type"] = "application/json",
            ["Host"] = "path.com",
          },
          body = {
            f1 = "abc"
          }
        })
        assert.res_status(200, res)


        local res = assert(proxy_client:send {
          method = "GET",
          path = "/resources/.1.2.3/anything",
          headers = {
            ["Content-Type"] = "application/json",
            ["Host"] = "path.com",
          },
          body = {
            f1 = "abc"
          }
        })
        assert.res_status(400, res)
      end)

      it("location: path, style: matrix, explode:false schema_type: array item_type: integer", function()
        local body_schema = [[
          [
            {
              "f1": {
                "type": "string"
              }
            }
          ]
        ]]

        local param_schema = {
          {
            name = "resource_id",
            ["in"] = "path",
            required = true,
            schema = '{"type": "array", "items": {"type": "integer"}}',
            style = "matrix",
            explode = false,
          }
        }


        add_plugin(admin_client, {body_schema = body_schema, parameter_schema = param_schema}, 201)

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/resources/;resource_id=1,2,3/anything",
          headers = {
            ["Content-Type"] = "application/json",
            ["Host"] = "path.com",
          },
          body = {
            f1 = "abc"
          }
        })
        assert.res_status(200, res)


        local res = assert(proxy_client:send {
          method = "GET",
          path = "/resources/;resource_id:1;resource_id:2;resource_id:3/anything",
          headers = {
            ["Content-Type"] = "application/json",
            ["Host"] = "path.com",
          },
          body = {
            f1 = "abc"
          }
        })
        assert.res_status(400, res)
      end)

      it("location: path, style: matrix, explode:true schema_type: array item_type: string", function()
        local body_schema = [[
          [
            {
              "f1": {
                "type": "string"
              }
            }
          ]
        ]]

        local param_schema = {
          {
            name = "resource_id",
            ["in"] = "path",
            required = true,
            schema = '{"type": "array", "items": {"type": "integer"}}',
            style = "matrix",
            explode = true,
          }
        }


        add_plugin(admin_client, {body_schema = body_schema, parameter_schema = param_schema}, 201)

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/resources/;resource_id=1,2,3/anything",
          headers = {
            ["Content-Type"] = "application/json",
            ["Host"] = "path.com",
          },
          body = {
            f1 = "abc"
          }
        })
        assert.res_status(400, res)


        local res = assert(proxy_client:send {
          method = "GET",
          path = "/resources/;resource_id=1;resource_id=2;resource_id=3/anything",
          headers = {
            ["Content-Type"] = "application/json",
            ["Host"] = "path.com",
          },
          body = {
            f1 = "abc"
          }
        })
        assert.res_status(200, res)
      end)

      it("location: path, style: matrix, explode:false schema_type: object item_type: string", function()
        local body_schema = [[
          [
            {
              "f1": {
                "type": "string"
              }
            }
          ]
        ]]

        local param_schema = {
          {
            name = "resource_id",
            ["in"] = "path",
            required = true,
            schema = [[
            {
              "type": "object",
              "required": ["a", "b"],
              "properties": {
                "a": {
                  "type": "string"
                },
                "b": {
                  "type": "string"
                }
              }
            }]],
            style = "matrix",
            explode = false,
          }
        }

        add_plugin(admin_client, {body_schema = body_schema, parameter_schema = param_schema}, 201)

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/resources/;resource_id=a,val_a,b,val_b/anything",
          headers = {
            ["Content-Type"] = "application/json",
            ["Host"] = "path.com",
          },
          body = {
            f1 = "abc"
          }
        })
        assert.res_status(200, res)


        local res = assert(proxy_client:send {
          method = "GET",
          path = "/resources/;a=val_a;b=val_b/anything",
          headers = {
            ["Content-Type"] = "application/json",
            ["Host"] = "path.com",
          },
          body = {
            f1 = "abc"
          }
        })
        assert.res_status(400, res)
      end)

      it("location: query, style: form, explode:false schema_type: object item_type: string", function()
        local body_schema = [[
          [
            {
              "f1": {
                "type": "string"
              }
            }
          ]
        ]]

        local param_schema = {
          {
            name = "id",
            ["in"] = "query",
            required = true,
            schema = [[
            {
              "type": "object",
              "required": ["a", "b"],
              "properties": {
                "a": {
                  "type": "string"
                },
                "b": {
                  "type": "string"
                }
              }
            }]],
            style = "form",
            explode = false,
          }
        }

        add_plugin(admin_client, {body_schema = body_schema, parameter_schema = param_schema}, 201)

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/anything?id=a,val_a,b,val_b",
          headers = {
            ["Content-Type"] = "application/json",
            ["Host"] = "path.com",
          },
          body = {
            f1 = "abc"
          }
        })
        assert.res_status(200, res)


        local res = assert(proxy_client:send {
          method = "GET",
          path = "/anything?id=a,val_a",
          headers = {
            ["Content-Type"] = "application/json",
            ["Host"] = "path.com",
          },
          body = {
            f1 = "abc"
          }
        })
        assert.res_status(400, res)
      end)

      it("location: query, style: form, explode:true schema_type: array item_type: integer", function()
        local body_schema = [[
          [
            {
              "f1": {
                "type": "string"
              }
            }
          ]
        ]]

        local param_schema = {
          {
            name = "id",
            ["in"] = "query",
            required = true,
            schema = '{"type": "array", "items": {"type": "integer"}}',
            style = "form",
            explode = true,
          }
        }


        add_plugin(admin_client, {body_schema = body_schema, parameter_schema = param_schema}, 201)

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/anything?id=1&id=2&id=3",
          headers = {
            ["Content-Type"] = "application/json",
            ["Host"] = "path.com",
          },
          body = {
            f1 = "abc"
          }
        })
        assert.res_status(200, res)


        local res = assert(proxy_client:send {
          method = "GET",
          path = "/anything?id=a&id=b&id=c",
          headers = {
            ["Content-Type"] = "application/json",
            ["Host"] = "path.com",
          },
          body = {
            f1 = "abc"
          }
        })
        assert.res_status(400, res)
      end)

      it("location: query, style: form, explode:false schema_type: array item_type: integer", function()
        local body_schema = [[
          [
            {
              "f1": {
                "type": "string"
              }
            }
          ]
        ]]

        local param_schema = {
          {
            name = "id",
            ["in"] = "query",
            required = true,
            schema = '{"type": "array", "items": {"type": "integer"}}',
            style = "form",
            explode = false,
          }
        }


        add_plugin(admin_client, {body_schema = body_schema, parameter_schema = param_schema}, 201)

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/anything?id=1,2,3",
          headers = {
            ["Content-Type"] = "application/json",
            ["Host"] = "path.com",
          },
          body = {
            f1 = "abc"
          }
        })
        assert.res_status(200, res)


        local res = assert(proxy_client:send {
          method = "GET",
          path = "/anything?id=1&id=2&id=3",
          headers = {
            ["Content-Type"] = "application/json",
            ["Host"] = "path.com",
          },
          body = {
            f1 = "abc"
          }
        })
        assert.res_status(400, res)
      end)

      it("location: query, style: spaceDelimited, explode:true schema_type: array item_type: integer", function()
        local body_schema = [[
          [
            {
              "f1": {
                "type": "string"
              }
            }
          ]
        ]]

        local param_schema = {
          {
            name = "id",
            ["in"] = "query",
            required = true,
            schema = '{"type": "array", "items": {"type": "integer"}}',
            style = "spaceDelimited",
            explode = true,
          }
        }

        add_plugin(admin_client, {body_schema = body_schema, parameter_schema = param_schema}, 201)


        local res = assert(proxy_client:send {
          method = "GET",
          path = "/anything?id=1&id=2&id=3",
          headers = {
            ["Content-Type"] = "application/json",
            ["Host"] = "path.com",
          },
          body = {
            f1 = "abc"
          }
        })
        assert.res_status(200, res)

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/anything?id=1 2 3",
          headers = {
            ["Content-Type"] = "application/json",
            ["Host"] = "path.com",
          },
          body = {
            f1 = "abc"
          }
        })
        assert.res_status(400, res)
      end)

      it("location: query, style: spaceDelimited, explode:false schema_type: array item_type: integer", function()
        local body_schema = [[
          [
            {
              "f1": {
                "type": "string"
              }
            }
          ]
        ]]

        local param_schema = {
          {
            name = "id",
            ["in"] = "query",
            required = true,
            schema = '{"type": "array", "items": {"type": "integer"}}',
            style = "spaceDelimited",
            explode = false,
          }
        }

        add_plugin(admin_client, {body_schema = body_schema, parameter_schema = param_schema}, 201)


        local res = assert(proxy_client:send {
          method = "GET",
          path = "/anything?id=1 2 3",
          headers = {
            ["Content-Type"] = "application/json",
            ["Host"] = "path.com",
          },
          body = {
            f1 = "abc"
          }
        })
        assert.res_status(200, res)

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/anything?id=1&id=2&id=3",
          headers = {
            ["Content-Type"] = "application/json",
            ["Host"] = "path.com",
          },
          body = {
            f1 = "abc"
          }
        })
        assert.res_status(400, res)
      end)

      it("location: query, style: pipeDelimited, explode:true schema_type: array item_type: integer", function()
        local body_schema = [[
          [
            {
              "f1": {
                "type": "string"
              }
            }
          ]
        ]]

        local param_schema = {
          {
            name = "id",
            ["in"] = "query",
            required = true,
            schema = '{"type": "array", "items": {"type": "integer"}}',
            style = "pipeDelimited",
            explode = true,
          }
        }

        add_plugin(admin_client, {body_schema = body_schema, parameter_schema = param_schema}, 201)


        local res = assert(proxy_client:send {
          method = "GET",
          path = "/anything?id=1&id=2&id=3",
          headers = {
            ["Content-Type"] = "application/json",
            ["Host"] = "path.com",
          },
          body = {
            f1 = "abc"
          }
        })
        assert.res_status(200, res)

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/anything?id=1|2|3",
          headers = {
            ["Content-Type"] = "application/json",
            ["Host"] = "path.com",
          },
          body = {
            f1 = "abc"
          }
        })
        assert.res_status(400, res)
      end)

      it("location: query, style: pipeDelimited, explode:false schema_type: array item_type: integer", function()
        local body_schema = [[
          [
            {
              "f1": {
                "type": "string"
              }
            }
          ]
        ]]

        local param_schema = {
          {
            name = "id",
            ["in"] = "query",
            required = true,
            schema = '{"type": "array", "items": {"type": "integer"}}',
            style = "pipeDelimited",
            explode = false,
          }
        }

        add_plugin(admin_client, {body_schema = body_schema, parameter_schema = param_schema}, 201)


        local res = assert(proxy_client:send {
          method = "GET",
          path = "/anything?id=1|2|3",
          headers = {
            ["Content-Type"] = "application/json",
            ["Host"] = "path.com",
          },
          body = {
            f1 = "abc"
          }
        })
        assert.res_status(200, res)

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/anything?id=1&id=2&id=3",
          headers = {
            ["Content-Type"] = "application/json",
            ["Host"] = "path.com",
          },
          body = {
            f1 = "abc"
          }
        })
        assert.res_status(400, res)
      end)

      it("location: query, style: deepObject, explode:true schema_type: object item_type: string", function()
        local body_schema = [[
          [
            {
              "f1": {
                "type": "string"
              }
            }
          ]
        ]]

        local param_schema = {
          {
            name = "id",
            ["in"] = "query",
            required = true,
            schema = [[
            {
              "type": "object",
              "required": ["a", "b"],
              "properties": {
                "a": {
                  "type": "string"
                },
                "b": {
                  "type": "string"
                }
              }
            }]],
            style = "deepObject",
            explode = true,
          }
        }

        add_plugin(admin_client, {body_schema = body_schema, parameter_schema = param_schema}, 201)

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/anything?id[a]=val_a&id[b]=val_b",
          headers = {
            ["Content-Type"] = "application/json",
            ["Host"] = "path.com",
          },
          body = {
            f1 = "abc"
          }
        })
        assert.res_status(200, res)

        -- should fail as id is required field
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/anything",
          headers = {
            ["Content-Type"] = "application/json",
            ["Host"] = "path.com",
          },
          body = {
            f1 = "abc"
          }
        })
        assert.res_status(400, res)
      end)

      it("multiple parameters validation", function()
        local body_schema = [[
          [
            {
              "f1": {
                "type": "string"
              }
            }
          ]
        ]]

        local param_schema = {
          {
            name = "id",
            ["in"] = "query",
            required = false,
            schema = [[
            {
              "type": "object",
              "required": ["a", "b"],
              "properties": {
                "a": {
                  "type": "string"
                },
                "b": {
                  "type": "string"
                }
              }
            }]],
            style = "deepObject",
            explode = true,
          }
        }

        add_plugin(admin_client, {body_schema = body_schema, parameter_schema = param_schema}, 201)

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/anything",
          headers = {
            ["Content-Type"] = "application/json",
            ["Host"] = "path.com",
          },
          body = {
            f1 = "abc"
          }
        })
        assert.res_status(200, res)
      end)


      it("location: query, style: deepObject, explode:true schema_type: object item_type: string required: false", function()
        local body_schema = [[
          [
            {
              "f1": {
                "type": "string"
              }
            }
          ]
        ]]

        local param_schema = {
          {
            name = "id",
            ["in"] = "query",
            required = true,
            schema = [[
            {
              "type": "object",
              "required": ["a", "b"],
              "properties": {
                "a": {
                  "type": "string"
                },
                "b": {
                  "type": "string"
                }
              }
            }]],
            style = "deepObject",
            explode = true,
          },
          {
            name = "x-kong-name",
            ["in"] = "header",
            required = true,
            schema = '{"type": "array", "items": {"type": "string"}}',
            style = "simple",
            explode = true,
          }
        }

        add_plugin(admin_client, {body_schema = body_schema, parameter_schema = param_schema}, 201)

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/anything?id[a]=val_a&id[b]=val_b",
          headers = {
            ["Content-Type"] = "application/json",
            ["Host"] = "path.com",
          },
          body = {
            f1 = "abc"
          }
        })
        assert.res_status(400, res)

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/anything",
          headers = {
            ["Content-Type"] = "application/json",
            ["Host"] = "path.com",
            ["x-kong-name"] = "a,b,c",
          },
          body = {
            f1 = "abc"
          }
        })
        assert.res_status(400, res)

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/anything?id[a]=val_a&id[b]=val_b",
          headers = {
            ["Content-Type"] = "application/json",
            ["Host"] = "path.com",
            ["x-kong-name"] = "a,b,c",
          },
          body = {
            f1 = "abc"
          }
        })
        assert.res_status(200, res)
      end)
    end)
  end)
end
