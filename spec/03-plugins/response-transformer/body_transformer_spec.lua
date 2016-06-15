local body_transformer = require "kong.plugins.response-transformer.body_transformer"
local cjson = require "cjson"

describe("Plugin: response transformer", function()
  describe("transform_json_body()", function()
    describe("add", function()
      local conf = {
        remove = {
          json = {}
        },
        replace = {
          json = {}
        },
        add = {
          json = {"p1:v1", "p3:v3", "p4:\"v1\""}
        },
        append = {
          json = {}
        },
      }
      it("parameter", function()
        local json = [[{"p2":"v1"}]]
        local body = body_transformer.transform_json_body(conf, json)
        local body_json = cjson.decode(body)
        assert.same({p1 = "v1", p2 = "v1", p3 = "v3", p4 = '"v1"'}, body_json)
      end)
      it("add value in double quotes", function()
        local json = [[{"p2":"v1"}]]
        local body = body_transformer.transform_json_body(conf, json)
        local body_json = cjson.decode(body)
        assert.same({p1 = "v1", p2 = "v1", p3 = "v3", p4 = '"v1"'}, body_json)
      end)
    end)

    describe("append", function()
      local conf = {
        remove = {
          json = {}
        },
        replace = {
          json = {}
        },
        add = {
          json = {}
        },
        append = {
          json = {"p1:v1", "p3:\"v1\""}
        },
      }
      it("new key:value if key does not exists", function()
        local json = [[{"p2":"v1"}]]
        local body = body_transformer.transform_json_body(conf, json)
        local body_json = cjson.decode(body)
        assert.same({ p2 = "v1", p1 = {"v1"}, p3 = {'"v1"'}}, body_json)
      end)
      it("value if key exists", function()
        local json = [[{"p1":"v2"}]]
        local body = body_transformer.transform_json_body(conf, json)
        local body_json = cjson.decode(body)
        assert.same({ p1 = {"v2","v1"}, p3 = {'"v1"'}}, body_json)
      end)
      it("value in double quotes", function()
        local json = [[{"p3":"v2"}]]
        local body = body_transformer.transform_json_body(conf, json)
        local body_json = cjson.decode(body)
        assert.same({p1 = {"v1"}, p3 = {"v2",'"v1"'}}, body_json)
      end)
    end)

    describe("remove", function()
      local conf = {
        remove = {
          json = {"p1", "p2"}
        },
        replace = {
          json = {}
        },
        add = {
          json = {}
        },
        append = {
          json = {}
        }
      }
      it("parameter", function()
        local json = [[{"p1" : "v1", "p2" : "v1"}]]
        local body = body_transformer.transform_json_body(conf, json)
        assert.equal("{}", body)
      end)
    end)

    describe("replace", function()
      local conf = {
        remove = {
          json = {}
        },
        replace = {
          json = {"p1:v2", "p2:\"v2\""}
        },
        add = {
          json = {}
        },
        append = {
          json = {}
        }
      }
      it("parameter if it exists", function()
        local json = [[{"p1" : "v1", "p2" : "v1"}]]
        local body = body_transformer.transform_json_body(conf, json)
        local body_json = cjson.decode(body)
        assert.same({p1 = "v2", p2 = '"v2"'}, body_json)
      end)
      it("does not add value to parameter if parameter does not exists", function()
        local json = [[{"p1" : "v1"}]]
        local body = body_transformer.transform_json_body(conf, json)
        local body_json = cjson.decode(body)
        assert.same({p1 = "v2"}, body_json)
      end)
      it("double quoted value", function()
        local json = [[{"p2" : "v1"}]]
        local body = body_transformer.transform_json_body(conf, json)
        local body_json = cjson.decode(body)
        assert.same({p2 = '"v2"'}, body_json)
      end)
    end)

    describe("remove, replace, add, append", function()
      local conf = {
        remove = {
          json = {"p1"}
        },
        replace = {
          json = {"p2:v2"}
        },
        add = {
          json = {"p3:v1"}
        },
        append = {
          json = {"p3:v2"}
        },
      }
      it("combination", function()
        local json = [[{"p1" : "v1", "p2" : "v1"}]]
        local body = body_transformer.transform_json_body(conf, json)
        local body_json = cjson.decode(body)
        assert.same({p2 = "v2", p3 = {"v1", "v2"}}, body_json)
      end)
    end)
  end)

  describe("is_json_body()", function()
    it("is truthy when content-type application/json passed", function()
        assert.truthy(body_transformer.is_json_body("application/json"))
        assert.truthy(body_transformer.is_json_body("application/json; charset=utf-8"))
    end)
    it("is truthy when content-type is multiple values along with application/json passed", function()
        assert.truthy(body_transformer.is_json_body("application/x-www-form-urlencoded, application/json"))
    end)
    it("is falsy when content-type not application/json", function()
        assert.falsy(body_transformer.is_json_body("application/x-www-form-urlencoded"))
    end)
  end)
end)