local body_transformer = require "kong.plugins.response-transformer.body_transformer"
local cjson = require "cjson"

describe("Plugin: response-transformer", function()
  describe("transform_json_body()", function()
    describe("add", function()
      local conf = {
        remove   = {
          json   = {}
        },
        replace  = {
          json   = {}
        },
        add      = {
          json   = {"p1:v1", "p3:value:3", "p4:\"v1\""}
        },
        append   = {
          json   = {}
        },
      }
      it("parameter", function()
        local json = [[{"p2":"v1"}]]
        local body = body_transformer.transform_json_body(conf, json)
        local body_json = cjson.decode(body)
        assert.same({p1 = "v1", p2 = "v1", p3 = "value:3", p4 = '"v1"'}, body_json)
      end)
      it("add value in double quotes", function()
        local json = [[{"p2":"v1"}]]
        local body = body_transformer.transform_json_body(conf, json)
        local body_json = cjson.decode(body)
        assert.same({p1 = "v1", p2 = "v1", p3 = "value:3", p4 = '"v1"'}, body_json)
      end)
    end)

    describe("append", function()
      local conf = {
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
          json   = {"p1:v1", "p3:\"v1\""}
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
        remove   = {
          json   = {"p1", "p2"}
        },
        replace  = {
          json   = {}
        },
        add      = {
          json   = {}
        },
        append   = {
          json   = {}
        }
      }
      it("parameter", function()
        local json = [[{"p1" : "v1", "p2" : "v1"}]]
        local body = body_transformer.transform_json_body(conf, json)
        assert.equals("{}", body)
      end)
    end)

    describe("replace", function()
      local conf = {
        remove   = {
          json   = {}
        },
        replace  = {
          json   = {"p1:v2", "p2:\"v2\""}
        },
        add      = {
          json   = {}
        },
        append   = {
          json   = {}
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
        remove   = {
          json   = {"p1"}
        },
        replace  = {
          json   = {"p2:v2"}
        },
        add      = {
          json   = {"p3:v1"}
        },
        append   = {
          json   = {"p3:v2"}
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

  describe("leave body alone", function()
    -- Related to issue https://github.com/Kong/kong/issues/1207
    -- unit test to check body remains unaltered

    local old_ngx, handler

    lazy_setup(function()
      old_ngx  = ngx
      _G.ngx   = {       -- busted requires explicit _G to access the global environment
        log    = function() end,
        header = {
          ["content-type"] = "application/json",
        },
        arg    = {},
        ctx    = {
          buffer = "",
        },
      }
      handler = require("kong.plugins.response-transformer.handler")
      handler:new()
    end)

    lazy_teardown(function()
      -- luacheck: globals ngx
      ngx = old_ngx
    end)

    it("body remains unaltered if no transforms have been set", function()
      -- only a header transform, no body changes
      local conf  = {
        remove    = {
          headers = {"h1", "h2", "h3"},
          json    = {}
        },
        add       = {
          headers = {},
          json    = {},
        },
        append    = {
          headers = {},
          json    = {},
        },
        replace   = {
          headers = {},
          json    = {},
        },
      }
      local body = [[

    {
      "id": 1,
      "name": "Some One",
      "username": "Bretchen",
      "email": "Not@here.com",
      "address": {
        "street": "Down Town street",
        "suite": "Apt. 23",
        "city": "Gwendoline"
      },
      "phone": "1-783-729-8531 x56442",
      "website": "hardwork.org",
      "company": {
        "name": "BestBuy",
        "catchPhrase": "just a bunch of words",
        "bs": "bullshit words"
      }
    }

  ]]

      ngx.arg[1] = body
      handler:body_filter(conf)
      local result = ngx.arg[1]
      ngx.arg[1] = ""
      ngx.arg[2] = true -- end of body marker
      handler:body_filter(conf)
      result = result .. ngx.arg[1]

      -- body filter should not execute, it would parse and re-encode the json, removing
      -- the whitespace. So check equality to make sure whitespace is still there, and hence
      -- body was not touched.
      assert.are.same(body, result)
    end)
  end)
end)
