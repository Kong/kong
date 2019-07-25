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
      }

      it("skips replace transform if response code doesn't match", function()
        local json = [[{"p2" : "v1"}]]
        local body = body_transformer.transform_json_body(conf_skip, json, 200)
        local body_json = cjson.decode(body)
        assert.same({p2 = "v1"}, body_json)
      end)
    end)

    describe("transform", function()
      local transform_function = [[
        return function (key, data)
          if key and key == "quantity" then
            key = "inventory"
            if data <= 0 then
              data = "none"
            elseif data >= 1 and data <= 10 then
              data = "small"
            elseif data > 10 and data <= 50 then
              data = "medium"
            else
              data = "large"
            end
          end

          return key, data
        end
      ]]

      local conf = {
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
          functions = { transform_function },
        },
      }

      it("performs arbitrary transformations on body #transform", function()
        local json = [[
          {
            "something": {
              "deeply": {
                "nested": {
                  "array": [
                    { "name": "hats", "quantity": 0 },
                    { "name": "t-shirts", "quantity": 10 },
                    { "name": "swag", "quantity": 40 },
                    { "name": "hoodies", "quantity": 9001 }
                  ],
                  "or_by_key": {
                    "hats": { "quantity": 0 },
                    "t-shirts": { "quantity": 10 },
                    "swag": { "quantity": 40 },
                    "hoodies": { "quantity": 9001 }
                  }
                }
              }
            }
          }
        ]]

        local expected = {
          something = {
            deeply = {
              nested = {
                array = {
                  { name = "hats", inventory = "none" },
                  { name = "t-shirts", inventory = "small" },
                  { name = "swag", inventory = "medium" },
                  { name = "hoodies", inventory = "large" },
                },
                ["or_by_key"] = {
                  ["hats"] = { inventory = "none" },
                  ["t-shirts"] = { inventory = "small" },
                  ["swag"] = { inventory = "medium" },
                  ["hoodies"] = { inventory = "large" },
                }
              }
            }
          }
        }

        local body = body_transformer.transform_json_body(conf, json, 200)
        local body_json = cjson.decode(body)
        assert.same(expected, body_json)
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
