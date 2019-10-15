local body_transformer = require "kong.plugins.response-transformer-advanced.body_transformer"
local cjson = require "cjson"

describe("Plugin: response-transformer-advanced", function()
  describe("transform_json_body()", function()
    describe("add", function()
      local conf_skip = {
        remove   = {
          json   = {}
        },
        replace  = {
          json   = {}
        },
        add      = {
          json   = {"p1:v1", "p3:value:3", "p4:\"v1\""},
          if_status = {"500"}
        },
        append   = {
          json   = {}
        },
        whitelist   = {
          json   = {},
        },
        transform = {
          functions = {},
        },
      }

      it("skips 'add' transform if response status doesn't match", function()
        local json = [[{"p2":"v1"}]]
        local body = body_transformer.transform_json_body(conf_skip, json, 200)
        local body_json = cjson.decode(body)
        assert.same({p2 = "v1"}, body_json)
      end)
    end)

    describe("append", function()
      local conf_skip = {
        remove   = {
          json   = {}
        },
        replace  = {
          json   = {}
        },
        add      = {
          json   = {}
        },
        append   = {
          json   = {"p1:v1", "p3:\"v1\""},
          if_status = {"500"}
        },
        whitelist   = {
          json   = {},
        },
        transform = {
          functions = {},
        },
      }

      it("skips append transform if response status doesn't match", function()
        local json = [[{"p3":"v2"}]]
        local body = body_transformer.transform_json_body(conf_skip, json, 200)
        local body_json = cjson.decode(body)
        assert.same({p3 = "v2"}, body_json)
      end)
    end)

    describe("remove", function()
      local conf_skip = {
        remove   = {
          json   = {"p1", "p2"},
          if_status = {"500"}
        },
        replace  = {
          json   = {}
        },
        add      = {
          json   = {}
        },
        append   = {
          json   = {}
        },
        whitelist   = {
          json   = {}
        },
        transform = {
          functions = {},
        },
      }

      it("skips remove transform if response status doesn't match", function()
        local json = [[{"p1" : "v1", "p2" : "v1"}]]
        local body = body_transformer.transform_json_body(conf_skip, json, 200)
        local body_json = cjson.decode(body)
        assert.same({p1 = "v1", p2 = "v1"}, body_json)
      end)
    end)

    describe("whitelist", function()
      local conf_skip = {
        whitelist   = {
          json   = {"p1", "p2"},
          if_status = {"500"}
        },
        replace  = {
          json   = {}
        },
        remove  = {
          json   = {}
        },
        add      = {
          json   = {}
        },
        append   = {
          json   = {}
        },
        transform = {
          functions = {},
        },
      }

      it("skips filter transform if response status doesn't match", function()
        local json = [[{"p1" : "v1", "p2" : "v1"}]]
        local body = body_transformer.transform_json_body(conf_skip, json, 200)
        local body_json = cjson.decode(body)
        assert.same({p1 = "v1", p2 = "v1"}, body_json)
      end)
    end)

    describe("replace", function()
      local conf_skip = {
        remove   = {
          json   = {}
        },
        replace  = {
          json   = {"p1:v2", "p2:\"v2\""},
          if_status = {"500"}
        },
        add      = {
          json   = {}
        },
        append   = {
          json   = {}
        },
        whitelist   = {
          json   = {},
        },
        transform = {
          functions = {},
        },
      }

      it("skips replace transform if response code doesn't match", function()
        local json = [[{"p2" : "v1"}]]
        local body = body_transformer.transform_json_body(conf_skip, json, 200)
        local body_json = cjson.decode(body)
        assert.same({p2 = "v1"}, body_json)
      end)
    end)

    describe("transform", function()
      local conf

      before_each(function()
        conf = {
          remove   = {
            json   = {}
          },
          replace  = {
            json   = {},
          },
          add      = {
            json   = {}
          },
          append   = {
            json   = {}
          },
          whitelist = {
            json   = {},
          },
          transform = {
            functions = {}
          },
        }
      end)

      it("performs simple transformmations on body transform", function()
        local transform_function = [[
          return function(data)
            -- remove key foo
            data["foo"] = nil
            -- add key foobar
            data["foobar"] = "hello world"
            -- ...
            return data
          end
        ]]

        local json = [[
          {
            "foo": "bar",
            "something": "else"
          }
        ]]

        local expected = {
          foobar = "hello world",
          something = "else",
        }

        conf.transform.functions = { transform_function }
        local body = body_transformer.transform_json_body(conf, json, 200)
        local body_json = cjson.decode(body)
        assert.same(expected, body_json)
      end)

      it("reduces over transform functions", function()
        local transform_functions = {
          [[
            return function(data)
              -- remove key foo
              data["foo"] = nil
              -- increment counter
              data.counter = data.counter + 1

              return data
            end
          ]],
          [[
            return function(data)
              -- add key foobar
              data["foobar"] = "hello world"
              -- increment counter
              data.counter = data.counter + 1

              return data
            end
          ]],
        }

        local json = [[
          {
            "foo": "bar",
            "something": "else",
            "counter": 0
          }
        ]]

        local expected = {
          foobar = "hello world",
          something = "else",
          counter = 2
        }

        conf.transform.functions = transform_functions
        local body = body_transformer.transform_json_body(conf, json, 200)
        local body_json = cjson.decode(body)
        assert.same(expected, body_json)

      end)

      it("has no access to the global context", function()
        local some_function_that_access_global_ctx = [[
          return function (data)
            return type(_KONG)
          end
        ]]

        local json = [[
          { "some": "data" }
        ]]

        conf.transform.functions = { some_function_that_access_global_ctx }
        local body = body_transformer.transform_json_body(conf, json, 200)
        local body_json = cjson.decode(body)
        assert.same("nil", body_json)
      end)

      it("has its own context", function()
        local some_function_that_access_global_ctx = [[
          local foo = "bar"
          return function (data)
            return foo
          end
        ]]

        local json = [[
          { "some": "data" }
        ]]

        local expected = "bar"

        conf.transform.functions = { some_function_that_access_global_ctx }
        local body = body_transformer.transform_json_body(conf, json, 200)
        local body_json = cjson.decode(body)
        assert.same(expected, body_json)
      end)

      it("leaves response untouched on error (returned)", function()
        local some_function_that_access_global_ctx = [[
          local foo = "bar"
          return function (data)
            hello.darkness()
            return data
          end
        ]]

        local json = [[
          { "some": "data" }
        ]]

        local expected = { ["some"] = "data" }

        conf.transform.functions = { some_function_that_access_global_ctx }

        local body, err = body_transformer.transform_json_body(conf, json, 200)
        local body_json = cjson.decode(body)
        assert.same(expected, body_json)
        assert.not_nil(err)
      end)
    end)

    describe("remove, replace, add, append", function()
      local conf_skip = {
        remove   = {
          json   = {"p1"},
          if_status = {"500"}
        },
        replace  = {
          json   = {"p2:v2"},
          if_status = {"500"}
        },
        add      = {
          json   = {"p3:v1"},
          if_status = {"500"}
        },
        append   = {
          json   = {"p3:v2"},
          if_status = {"500"}
        },
        whitelist   = {
          json   = {}
        },
        transform = {
          functions = {},
        },
      }

      it("skips all transforms whose response code don't match", function()
        local json = [[{"p1" : "v1", "p2" : "v1"}]]
        local body = body_transformer.transform_json_body(conf_skip, json, 200)
        local body_json = cjson.decode(body)
        assert.same({p1 = "v1", p2 = "v1"}, body_json)
      end)
    end)
  end)

  describe("replace_body()", function()
    it("replaces entire body if enabled without status code filter", function()
      local conf = {
        replace  = {
          body = [[{"error": "server error"}]],
        },
      }
      local original_body = [[{"error": "error message with sensitive data"}]]
      local body = body_transformer.replace_body(conf, original_body, 200)
      assert.same([[{"error": "server error"}]], body)
      body = body_transformer.replace_body(conf, original_body, 400)
      assert.same([[{"error": "server error"}]], body)
      body = body_transformer.replace_body(conf, original_body, 500)
      assert.same([[{"error": "server error"}]], body)
    end)
    it("replaces entire body only in specified response codes", function()
      local conf = {
        replace  = {
          body = [[{"error": "server error"}]],
          if_status = {"200", "400"}
        },
      }
      local original_body = [[{"error": "error message with sensitive data"}]]
      local body = body_transformer.replace_body(conf, original_body, 200)
      assert.same([[{"error": "server error"}]], body)
      body = body_transformer.replace_body(conf, original_body, 400)
      assert.same([[{"error": "server error"}]], body)
      body = body_transformer.replace_body(conf, original_body, 500)
      assert.same(nil, body)
    end)
    it("doesn't replace entire body if response code doesn't match", function()
      local conf = {
        replace  = {
          body = [[{"error": "server error"}]],
          if_status = {"500"}
        },
      }
      local original_body = [[{"error": "error message with sensitive data"}]]
      local body = body_transformer.replace_body(conf, original_body, 200)
      assert.same(nil, body)
      body = body_transformer.replace_body(conf, original_body, 400)
      assert.same(nil, body)
    end)
  end)


  describe("filter body", function()
    it("filter body if enabled without status code filter", function()
      local conf = {
        whitelist   = {
          json   = {"p1"},
          if_status = {"200"}
        },
        replace  = {
          json   = {}
        },
        remove  = {
          json   = {}
        },
        add      = {
          json   = {}
        },
        append   = {
          json   = {}
        },
        transform = {
          functions = {},
        },
      }
      local original_body = [[{"p1" : "v1", "p2" : "v1"}]]
      local body = body_transformer.transform_json_body(conf, original_body, 200)
      assert.same([[{"p1":"v1"}]], body)
    end)
  end)
end)
