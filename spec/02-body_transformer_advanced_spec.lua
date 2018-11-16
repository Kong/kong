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
        }
      }

      it("skips remove transform if response status doesn't match", function()
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
        }
      }

      it("skips replace transform if response code doesn't match", function()
        local json = [[{"p2" : "v1"}]]
        local body = body_transformer.transform_json_body(conf_skip, json, 200)
        local body_json = cjson.decode(body)
        assert.same({p2 = "v1"}, body_json)
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
      }

      it("skips all transforms whose response code don't match", function()
        local json = [[{"p1" : "v1", "p2" : "v1"}]]
        local body = body_transformer.transform_json_body(conf_skip, json, 200)
        local body_json = cjson.decode(body)
        assert.same({p1 = "v1", p2 = "v1"}, body_json)
      end)
    end)
  end)
end)
