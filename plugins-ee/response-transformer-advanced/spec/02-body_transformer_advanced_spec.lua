-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local body_transformer = require "kong.plugins.response-transformer-advanced.body_transformer"
local cjson = require("cjson.safe").new()
cjson.decode_array_with_array_mt(true)
local decode_base64 = ngx.decode_base64
local encode_base64 = ngx.encode_base64
local inflate_gzip = require("kong.tools.utils").inflate_gzip
local deflate_gzip = require("kong.tools.utils").deflate_gzip

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
          json   = {"p1:v1", "p3:value:3", "p4:\"v1\"", "p5:-1", "p6:false", "p7:true"},
          json_types = {"string", "string", "string", "number", "boolean", "boolean"},
          if_status  = {"500"}
        },
        append   = {
          json   = {}
        },
        allow   = {
          json   = {},
        },
        transform = {
          json = {},
          functions = {},
        },
      }

      it("skips 'add' transform if response status doesn't match", function()
        local json = [[{"p2":"v1"}]]
        local transform_ops =  table.new(0, 7)
        transform_ops = body_transformer.determine_transform_operations(conf_skip, 200, transform_ops)
        local body = body_transformer.transform_json_body(conf_skip, json, transform_ops)
        local body_json = cjson.decode(body)
        assert.same({p2 = "v1"}, body_json)
      end)

      it("preserves empty arrays", function()
        local json = [[{"p2":"v1", "a":[]}]]

        -- status code matches
        local transform_ops =  table.new(0, 7)
        transform_ops = body_transformer.determine_transform_operations(conf_skip, 500, transform_ops)
        local body = body_transformer.transform_json_body(conf_skip, json, transform_ops)
        local body_json = cjson.decode(body)
        assert.same({p1 = "v1", p2 = "v1", p3 = "value:3", p4 = '"v1"', p5 = -1, p6 = false, p7 = true, a = {}}, body_json)
        assert.equals('[]', cjson.encode(body_json.a))

        -- status code doesn't match
        local transform_ops =  table.new(0, 7)
        transform_ops = body_transformer.determine_transform_operations(conf_skip, 200, transform_ops)
        body = body_transformer.transform_json_body(conf_skip, json, transform_ops)
        body_json = cjson.decode(body)
        assert.same({p2 = "v1", a = {}}, body_json)
        assert.equals('[]', cjson.encode(body_json.a))
      end)

      it("number", function()
        local json = [[{"p2":-1}]]

        -- status code matches
        local transform_ops =  table.new(0, 7)
        transform_ops = body_transformer.determine_transform_operations(conf_skip, 500, transform_ops)
        local body = body_transformer.transform_json_body(conf_skip, json, transform_ops)
        local body_json = cjson.decode(body)
        assert.same({p1 = "v1", p2 = -1, p3 = "value:3", p4 = '"v1"', p5 = -1, p6 = false, p7 = true}, body_json)

        -- status code doesn't match
        local transform_ops =  table.new(0, 7)
        transform_ops = body_transformer.determine_transform_operations(conf_skip, 200, transform_ops)
        body = body_transformer.transform_json_body(conf_skip, json, transform_ops)
        body_json = cjson.decode(body)
        assert.same({p2 = -1}, body_json)
      end)

      it("boolean", function()
        local json = [[{"p2":false}]]

        -- status code matches
        local transform_ops =  table.new(0, 7)
        transform_ops = body_transformer.determine_transform_operations(conf_skip, 500, transform_ops)
        local body = body_transformer.transform_json_body(conf_skip, json, transform_ops)
        local body_json = cjson.decode(body)
        assert.same({p1 = "v1", p2 = false, p3 = "value:3", p4 = '"v1"', p5 = -1, p6 = false, p7 = true}, body_json)

        -- status code doesn't match
        local transform_ops =  table.new(0, 7)
        transform_ops = body_transformer.determine_transform_operations(conf_skip, 200, transform_ops)
        body = body_transformer.transform_json_body(conf_skip, json, transform_ops)
        body_json = cjson.decode(body)
        assert.same({p2 = false}, body_json)
      end)

      it("string", function()
        local json = [[{"p2":"v1"}]]

        -- status code matches
        local transform_ops =  table.new(0, 7)
        transform_ops = body_transformer.determine_transform_operations(conf_skip, 500, transform_ops)
        local body = body_transformer.transform_json_body(conf_skip, json, transform_ops)
        local body_json = cjson.decode(body)
        assert.same({p1 = "v1", p2 = "v1", p3 = "value:3", p4 = '"v1"', p5 = -1, p6 = false, p7 = true}, body_json)

        -- status code doesn't match
        local transform_ops =  table.new(0, 7)
        transform_ops = body_transformer.determine_transform_operations(conf_skip, 200, transform_ops)
        body = body_transformer.transform_json_body(conf_skip, json, transform_ops)
        body_json = cjson.decode(body)
        assert.same({p2 = "v1"}, body_json)
      end)

      it("array", function()
        local json = [=[ [{ "p1": "v1" }, { "p1": "v1" }, { "p2": "v1" }] ]=]
        local config = { add = { json = { "[*].p2:v2" } } }

        local transform_ops =  table.new(0, 7)
        transform_ops = body_transformer.determine_transform_operations(conf_skip, 500, transform_ops)
        local body = body_transformer.transform_json_body(config, json, transform_ops)
        local body_json = cjson.decode(body)
        assert.same({{ p1 = "v1", p2 = "v2" }, { p1 = "v1", p2 = "v2" }, { p2 = "v1" }}, body_json)
      end)

      it("nested", function()
        local json = [[ { "p1": { "p1": "v1" }} ]]
        local config = { add = { json = { "p1.p2:v2" } } }

        local transform_ops =  table.new(0, 7)
        transform_ops = body_transformer.determine_transform_operations(conf_skip, 500, transform_ops)
        local body = body_transformer.transform_json_body(config, json, transform_ops)
        local body_json = cjson.decode(body)
        assert.same({ p1 = { p1 = "v1", p2 = "v2" }}, body_json)
      end)

      it("dots in keys", function()
        local json = [[ { "p1": { "p1": "v1" }} ]]
        local config = { add = { json = { "p1.p2:v2" } }, dots_in_keys = true }

        local transform_ops =  table.new(0, 7)
        transform_ops = body_transformer.determine_transform_operations(conf_skip, 500, transform_ops)
        local body = body_transformer.transform_json_body(config, json, transform_ops)
        local body_json = cjson.decode(body)
        assert.same({ p1 = { p1 = "v1" }, ["p1.p2"] = "v2" }, body_json)
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
          json   = {"p1:v1", "p3:\"v1\"", "p4:-1", "p5:false", "p6:true"},
          json_types = {"string", "string", "number", "boolean", "boolean"},
          if_status = {"500"}
        },
        allow   = {
          json   = {},
        },
        transform = {
          json   = {},
          functions = {},
        },
      }

      it("skips append transform if response status doesn't match", function()
        local json = [[{"p3":"v2"}]]
        local transform_ops =  table.new(0, 7)
        transform_ops = body_transformer.determine_transform_operations(conf_skip, 200, transform_ops)
        local body = body_transformer.transform_json_body(conf_skip, json, transform_ops)
        local body_json = cjson.decode(body)
        assert.same({p3 = "v2"}, body_json)
      end)

      it("preserves empty arrays", function()
        local json = [[{"p2":"v1", "a":[]}]]

        -- status code matches
        local transform_ops =  table.new(0, 7)
        transform_ops = body_transformer.determine_transform_operations(conf_skip, 500, transform_ops)
        local body = body_transformer.transform_json_body(conf_skip, json, transform_ops)
        local body_json = cjson.decode(body)
        assert.same({ p2 = "v1", p1 = {"v1"}, p3 = {'"v1"'}, a = {}, p4 = {-1}, p5 = {false}, p6 = {true} }, body_json)
        assert.equals('[]', cjson.encode(body_json.a))

        -- status doesn't match
        local transform_ops =  table.new(0, 7)
        transform_ops = body_transformer.determine_transform_operations(conf_skip, 200, transform_ops)
        body = body_transformer.transform_json_body(conf_skip, json, transform_ops)
        body_json = cjson.decode(body)
        assert.same({ p2 = "v1", a = {} }, body_json)
        assert.equals('[]', cjson.encode(body_json.a))
      end)

      it("number", function()
        local json = [[{"p4":"v2"}]]

        -- status code matches
        local transform_ops =  table.new(0, 7)
        transform_ops = body_transformer.determine_transform_operations(conf_skip, 500, transform_ops)
        local body = body_transformer.transform_json_body(conf_skip, json, transform_ops)
        local body_json = cjson.decode(body)
        assert.same({p1 = {"v1"}, p3 = {'"v1"'}, p4={"v2", -1}, p5 = {false}, p6 = {true}}, body_json)

        -- status code doesn't match
        local transform_ops =  table.new(0, 7)
        transform_ops = body_transformer.determine_transform_operations(conf_skip, 200, transform_ops)
        body = body_transformer.transform_json_body(conf_skip, json, transform_ops)
        body_json = cjson.decode(body)
        assert.same({p4 = "v2"}, body_json)
      end)

      it("boolean", function()
        local json = [[{"p5":"v5", "p6":"v6"}]]

        -- status code matches
        local transform_ops =  table.new(0, 7)
        transform_ops = body_transformer.determine_transform_operations(conf_skip, 500, transform_ops)
        local body = body_transformer.transform_json_body(conf_skip, json, transform_ops)
        local body_json = cjson.decode(body)
        assert.same({p1 = {"v1"}, p3 = {'"v1"'}, p4={-1}, p5 = {"v5", false}, p6 = {"v6", true}}, body_json)

        -- status code doesn't match
        local transform_ops =  table.new(0, 7)
        transform_ops = body_transformer.determine_transform_operations(conf_skip, 200, transform_ops)
        body = body_transformer.transform_json_body(conf_skip, json, transform_ops)
        body_json = cjson.decode(body)
        assert.same({p5 = "v5", p6 = "v6"}, body_json)
      end)

      it("string", function()
        local json = [[{"p1":"v2"}]]

        -- status code matches
        local transform_ops =  table.new(0, 7)
        transform_ops = body_transformer.determine_transform_operations(conf_skip, 500, transform_ops)
        local body = body_transformer.transform_json_body(conf_skip, json, transform_ops)
        local body_json = cjson.decode(body)
        assert.same({p1 = {"v2", "v1"}, p3 = {'"v1"'}, p4={-1}, p5 = {false}, p6 = {true}}, body_json)

        -- status code doesn't match
        local transform_ops =  table.new(0, 7)
        transform_ops = body_transformer.determine_transform_operations(conf_skip, 200, transform_ops)
        body = body_transformer.transform_json_body(conf_skip, json, transform_ops)
        body_json = cjson.decode(body)
        assert.same({p1 = "v2"}, body_json)
      end)

      it("array", function()
        local json = [=[ [{"p1": "v1"}, {"p1": "v1"}, {"p1": "v1"}] ]=]
        local config = { append = { json = { "[3].p1:v2" } } }

        local transform_ops =  table.new(0, 7)
        transform_ops = body_transformer.determine_transform_operations(config, 500, transform_ops)
        local body = body_transformer.transform_json_body(config, json, transform_ops)
        local body_json = cjson.decode(body)
        assert.same({{ p1 = "v1" }, { p1 = "v1" }, { p1 = { "v1", "v2" }}}, body_json)
      end)

      it("nested", function()
        local json = [[ { "p1": { "p1": "v1" }} ]]
        local config = { append = { json = { "p1.p1:v2" } } }

        local transform_ops =  table.new(0, 7)
        transform_ops = body_transformer.determine_transform_operations(config, 500, transform_ops)
        local body = body_transformer.transform_json_body(config, json, transform_ops)
        local body_json = cjson.decode(body)
        assert.same({ p1 = { p1 = { "v1", "v2" }}}, body_json)
      end)

      it("dots in keys", function()
        local json = [[ { "p1": { "p1": "v1" }} ]]
        local config = { append = { json = { "p1.p1:v2" } }, dots_in_keys = true }

        local transform_ops =  table.new(0, 7)
        transform_ops = body_transformer.determine_transform_operations(config, 500, transform_ops)
        local body = body_transformer.transform_json_body(config, json, transform_ops)
        local body_json = cjson.decode(body)
        assert.same({ p1 = { p1 = "v1" }, ["p1.p1"] = { "v2" }}, body_json)
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
        allow   = {
          json   = {}
        },
        transform = {
          json   = {},
          functions = {},
        },
      }

      it("skips remove transform if response status doesn't match", function()
        local json = [[{"p1" : "v1", "p2" : "v1"}]]
        local transform_ops =  table.new(0, 7)
        transform_ops = body_transformer.determine_transform_operations(conf_skip, 200, transform_ops)
        local body = body_transformer.transform_json_body(conf_skip, json, transform_ops)
        local body_json = cjson.decode(body)
        assert.same({p1 = "v1", p2 = "v1"}, body_json)
      end)

      it("preserves empty arrays", function()
        local json = [[{"p1" : "v1", "p2" : "v1", "a": []}]]

        -- status code matches
        local transform_ops =  table.new(0, 7)
        transform_ops = body_transformer.determine_transform_operations(conf_skip, 500, transform_ops)
        local body = body_transformer.transform_json_body(conf_skip, json, transform_ops)
        local body_json = cjson.decode(body)
        assert.same({a = {}}, body_json)
        assert.equals('[]', cjson.encode(body_json.a))

        -- status code doesn't match
        local transform_ops =  table.new(0, 7)
        transform_ops = body_transformer.determine_transform_operations(conf_skip, 200, transform_ops)
        body = body_transformer.transform_json_body(conf_skip, json, transform_ops)
        body_json = cjson.decode(body)
        assert.same({p1 = "v1", p2 = "v1", a = {}}, body_json)
        assert.equals('[]', cjson.encode(body_json.a))
      end)

      it("array", function()
        local json = [=[{ "results": [{ "p1": "v1" }, { "p1": "v1" }, { "p2": "v1" }] }]=]
        local config = { remove = { json = { "results[1].p1", "results[2].p1" } } }

        local transform_ops =  table.new(0, 7)
        transform_ops = body_transformer.determine_transform_operations(config, 500, transform_ops)
        local body = body_transformer.transform_json_body(config, json, transform_ops)
        local body_json = cjson.decode(body)
        assert.same({ results = {{}, {}, { p2 = "v1" }}}, body_json)
      end)

      it("array doesn't match with config", function()
        local json = [=[{ "results": [{ "p1": "v1" }, { "p1": "v1" }, { "p2": "v1" }] }]=]
        local config = { remove = { json = { "result[*]" } } }

        local transform_ops =  table.new(0, 7)
        transform_ops = body_transformer.determine_transform_operations(config, 500, transform_ops)
        local body = body_transformer.transform_json_body(config, json, transform_ops)
        local body_json = cjson.decode(body)
        assert.same({ results = {{p1 = "v1"}, {p1 = "v1"}, { p2 = "v1" }}}, body_json)
      end)

      it("nested", function()
        local json = [[ { "p1": { "p1": "v1" }} ]]
        local config = { remove = { json = { "p1.p1" } } }

        local transform_ops =  table.new(0, 7)
        transform_ops = body_transformer.determine_transform_operations(config, 500, transform_ops)
        local body = body_transformer.transform_json_body(config, json, transform_ops)
        local body_json = cjson.decode(body)
        assert.same({ p1 = { } }, body_json)
      end)

      it("dots in keys", function()
        local json = [[ { "p1": { "p1": "v1" }} ]]
        local config = { remove = { json = { "p1.p1" } }, dots_in_keys = true }

        local transform_ops =  table.new(0, 7)
        transform_ops = body_transformer.determine_transform_operations(config, 500, transform_ops)
        local body = body_transformer.transform_json_body(config, json, transform_ops)
        local body_json = cjson.decode(body)
        assert.same({ p1 = { p1 = "v1" } }, body_json)
      end)
    end)

    describe("allow", function()
      local conf_skip = {
        allow   = {
          json   = {"p1", "p2", "a"},
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
          json   = {},
          functions = {},
        },
      }

      it("skips filter transform if response status doesn't match", function()
        local json = [[{"p1" : "v1", "p2" : "v1"}]]
        local transform_ops =  table.new(0, 7)
        transform_ops = body_transformer.determine_transform_operations(conf_skip, 200, transform_ops)
        local body = body_transformer.transform_json_body(conf_skip, json, transform_ops)
        local body_json = cjson.decode(body)
        assert.same({p1 = "v1", p2 = "v1"}, body_json)
      end)

      it("preserves empty arrays", function()
        local json = [[{"p1" : "v1", "p2" : "v1", "a": []}]]

        -- status code matches
        local transform_ops =  table.new(0, 7)
        transform_ops = body_transformer.determine_transform_operations(conf_skip, 500, transform_ops)
        local body = body_transformer.transform_json_body(conf_skip, json, transform_ops)
        local body_json = cjson.decode(body)
        assert.same({p1 = "v1", p2 = "v1", a = {}}, body_json)
        assert.equals('[]', cjson.encode(body_json.a))

        -- status code doesn't match
        local transform_ops =  table.new(0, 7)
        transform_ops = body_transformer.determine_transform_operations(conf_skip, 200, transform_ops)
        body = body_transformer.transform_json_body(conf_skip, json, transform_ops)
        body_json = cjson.decode(body)
        assert.same({p1 = "v1", p2 = "v1", a = {}}, body_json)
        assert.equals('[]', cjson.encode(body_json.a))
      end)

      it("nested support", function()
        local config = {
          allow = { json = {} },
          replace = { json = {} },
          remove = { json = {} },
          add = { json = {} },
          append = { json = {} },
          transform = { json = {}, functions = {} },
        }

        local test_cases = {
          {
            description = "case: should success if allow.json does not contain nested syntax",
            config = {
              allow = {
                json = { "key1", "key2" },
              }
            },
            input = [[
              {
                  "key1": {
                      "Accept": "*/*",
                      "Host": "httpbin.org"
                  },
                  "key2": [],
                  "key3": "value3"
              }
            ]],
            output = [[
              {
                  "key1": {
                      "Accept": "*/*",
                      "Host": "httpbin.org"
                  },
                  "key2": []
              }
            ]],
          },
          {
            description = "case: sanity",
            config = {
             allow = {
               json = { "headers.Host", "students.[*].age", "students.[*].location.country", "students.[*].hobbies", "students.[*].empty_array" },
             }
            },
            input = [[
              {
                  "headers": {
                      "Accept": "*/*",
                      "Host": "httpbin.org"
                  },
                  "students": [
                      {
                          "age": 1,
                          "name": "name1",
                          "location": {
                              "country": "country1",
                              "province": "province1"
                          },
                          "hobbies": ["a", "b", "c"],
                          "empty_array": []
                      },
                      {
                          "age": 2,
                          "name": "name2",
                          "location": {
                              "country": "country2",
                              "province": "province2"
                          },
                          "hobbies": ["c", "d", "e"],
                          "empty_array": []
                      }
                  ]
              }
            ]],
            output = [[
              {
                  "headers": {
                      "Host": "httpbin.org"
                  },
                  "students": [
                      {
                          "age": 1,
                          "location": {
                              "country": "country1"
                          },
                          "hobbies": ["a", "b", "c"],
                          "empty_array": []
                      },
                      {
                          "age": 2,
                          "location": {
                              "country": "country2"
                          },
                          "hobbies": ["c", "d", "e"],
                          "empty_array": []
                      }
                  ]
              }
            ]],
          },
          {
            description = "case: sanity for array",
            config = {
              allow = {
                json = { "[*].age" },
              }
            },
            input = [[
              [
                  {
                      "name": "Jane",
                      "age": 24,
                      "isEmployed": true
                  },
                  {
                      "name": "Jack",
                      "age": 44,
                      "isEmployed": true
                  }
              ]
            ]],
            output = [[
              [
                  {
                      "age": 24
                  },
                  {
                      "age": 44
                  }
              ]
            ]],
          },
          {
            description = "case: input misses headers.Host ",
            config = {
              allow = {
                json = { "headers.Host", "name" },
              }
            },
            input = [[
              {
                  "name": "name",
                  "other": "other"
              }
            ]],
            output = [[
              {
                  "name": "name"
              }
            ]],
          },
          {
            description = "case: input misses leaf element",
            config = {
              allow = {
                json = { "headers.Host" },
              }
            },
            input = [[
              {
                  "headers": {
                      "Accept": "*/*"
                  }
              }
            ]],
            output = [[
              {
                  "headers": {}
              }
            ]],
          },
          {
            description = "case: element of input misses properties",
            config = {
              allow = {
                json = { "[*].age" },
              }
            },
            input = [[
              [
                  {
                      "name": "Jane",
                      "isEmployed": true
                  },
                  {
                      "name": "Jack",
                      "isEmployed": true
                  }
              ]
            ]],
            output = [[
              [
                  {
                  },
                  {
                  }
              ]
            ]],
          },
          {
            description = "case: return orignal input as array length greater than the actual input,",
            config = {
              allow = {
                json = { "students.[2].age" },
              }
            },
            input = [[
              {
                  "students": [
                      {
                          "age": 1
                      }
                  ]
              }
            ]],
            output = [[
              {
                  "students": [
                      {
                          "age": 1
                      }
                  ]
              }
            ]],
          },
          {
            description = "case: only return the perticular element of array",
            config = {
              allow = {
                json = { "students.[2].age" },
              }
            },
            input = [[
              {
                  "students": [
                      {
                          "age": 1
                      },
                      {
                          "age": 2
                      }
                  ]
              }
            ]],
            output = [[
              {
                  "students": [
                      null,
                      {
                          "age": 2
                      }
                  ]
              }
            ]],
          },
        }

        for i, case in ipairs(test_cases) do
          local input = case.input
          local expected_output = case.output
          config.allow.json = case.config.allow.json

          local transform_ops =  table.new(0, 7)
          transform_ops = body_transformer.determine_transform_operations(config, 200, transform_ops)
          local pok, err = pcall(body_transformer.transform_json_body, config, input, transform_ops)
          assert.is_true(pok, "failed to test the case: " .. case.description .. ", err: " .. err)
          local output = err
          assert.same(cjson.decode(expected_output), cjson.decode(output),
            "assertion failed: " .. i .. " " .. case.description)
        end
      end)
    end)

    describe("replace", function()
      local conf_skip = {
        remove   = {
          json   = {}
        },
        replace  = {
          json   = {"p1:v2", "p2:\"v2\"", "p3:-1", "p4:false", "p5:true"},
          json_types = {"string", "string", "number", "boolean", "boolean"},
          if_status = {"500"}
        },
        add      = {
          json   = {}
        },
        append   = {
          json   = {}
        },
        allow   = {
          json   = {},
        },
        transform = {
          json   = {},
          functions = {},
        },
      }

      it("skips replace transform if response code doesn't match", function()
        local json = [[{"p2" : "v1"}]]
        local transform_ops =  table.new(0, 7)
        transform_ops = body_transformer.determine_transform_operations(conf_skip, 200, transform_ops)
        local body = body_transformer.transform_json_body(conf_skip, json, transform_ops)
        local body_json = cjson.decode(body)
        assert.same({p2 = "v1"}, body_json)
      end)

      it("preserves empty arrays", function()
        local json = [[{"p1" : "v1", "p2" : "v1", "a": []}]]

        -- status code matches
        local transform_ops =  table.new(0, 7)
        transform_ops = body_transformer.determine_transform_operations(conf_skip, 500, transform_ops)
        local body = body_transformer.transform_json_body(conf_skip, json, transform_ops)
        local body_json = cjson.decode(body)
        assert.same({p1 = "v2", p2 = '"v2"', a = {}}, body_json)
        assert.equals('[]', cjson.encode(body_json.a))

        -- status code doesn't match
        local transform_ops =  table.new(0, 7)
        transform_ops = body_transformer.determine_transform_operations(conf_skip, 200, transform_ops)
        local body = body_transformer.transform_json_body(conf_skip, json, transform_ops)
        local body_json = cjson.decode(body)
        assert.same({p1 = "v1", p2 = "v1", a = {}}, body_json)
        assert.equals('[]', cjson.encode(body_json.a))
      end)

      it("number", function()
        local json = [[{"p3" : "v1"}]]

        -- status code matches
        local transform_ops =  table.new(0, 7)
        transform_ops = body_transformer.determine_transform_operations(conf_skip, 500, transform_ops)
        local body = body_transformer.transform_json_body(conf_skip, json, transform_ops)
        local body_json = cjson.decode(body)
        assert.same({p3 = -1}, body_json)

        -- status code doesn't match
        local transform_ops =  table.new(0, 7)
        transform_ops = body_transformer.determine_transform_operations(conf_skip, 200, transform_ops)
        body = body_transformer.transform_json_body(conf_skip, json, transform_ops)
        body_json = cjson.decode(body)
        assert.same({p3 = "v1"}, body_json)
      end)

      it("boolean", function()
        local json = [[{"p4" : "v4", "p5" : "v5"}]]

        -- status code matches
        local transform_ops =  table.new(0, 7)
        transform_ops = body_transformer.determine_transform_operations(conf_skip, 500, transform_ops)
        local body = body_transformer.transform_json_body(conf_skip, json, transform_ops)
        local body_json = cjson.decode(body)
        assert.same({p4 = false, p5 = true}, body_json)

        -- status code doesn't match
        local transform_ops =  table.new(0, 7)
        transform_ops = body_transformer.determine_transform_operations(conf_skip, 200, transform_ops)
        body = body_transformer.transform_json_body(conf_skip, json, transform_ops)
        body_json = cjson.decode(body)
        assert.same({p4 = "v4", p5 = "v5"}, body_json)
      end)

      it("array", function()
        local json = [=[ [{ "p1": "v1" }, { "p1": "v1" }, { "p2": "v1" }] ]=]
        local config = { replace = { json = { "[*].p1:v2" } } }

        local transform_ops =  table.new(0, 7)
        transform_ops = body_transformer.determine_transform_operations(config, 500, transform_ops)
        local body = body_transformer.transform_json_body(config, json, transform_ops)
        local body_json = cjson.decode(body)
        assert.same({{ p1 = "v2" }, { p1 = "v2" }, { p2 = "v1" }}, body_json)
      end)

      it("nested", function()
        local json = [[ { "p1": { "p1": "v1" }} ]]
        local config = { replace = { json = { "p1.p1:v2" } } }

        local transform_ops =  table.new(0, 7)
        transform_ops = body_transformer.determine_transform_operations(config, 500, transform_ops)
        local body = body_transformer.transform_json_body(config, json, transform_ops)
        local body_json = cjson.decode(body)
        assert.same({ p1 = { p1 = "v2" } }, body_json)
      end)

      it("dots in keys", function()
        local json = [[ { "p1": { "p1": "v1" }} ]]
        local config = { replace = { json = { "p1.p1:v2" } }, dots_in_keys = true }

        local transform_ops =  table.new(0, 7)
        transform_ops = body_transformer.determine_transform_operations(config, 500, transform_ops)
        local body = body_transformer.transform_json_body(config, json, transform_ops)
        local body_json = cjson.decode(body)
        assert.same({ p1 = { p1 = "v1" } }, body_json)
      end)
    end)

    describe("transform", function()
      local conf

      _G.kong = { configuration = { untrusted_lua = 'sandbox' } }

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
          allow = {
            json   = {},
          },
          transform = {
            json = {},
            functions = {},
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
        local transform_ops =  table.new(0, 7)
        transform_ops = body_transformer.determine_transform_operations(conf, 200, transform_ops)
        local body = body_transformer.transform_json_body(conf, json, transform_ops)
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
        local transform_ops =  table.new(0, 7)
        transform_ops = body_transformer.determine_transform_operations(conf, 200, transform_ops)
        local body = body_transformer.transform_json_body(conf, json, transform_ops)
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
        local transform_ops =  table.new(0, 7)
        transform_ops = body_transformer.determine_transform_operations(conf, 200, transform_ops)
        local body = body_transformer.transform_json_body(conf, json, transform_ops)
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
        local transform_ops =  table.new(0, 7)
        transform_ops = body_transformer.determine_transform_operations(conf, 200, transform_ops)
        local body = body_transformer.transform_json_body(conf, json, transform_ops)
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

        local transform_ops =  table.new(0, 7)
        transform_ops = body_transformer.determine_transform_operations(conf, 200, transform_ops)
        local body, err = body_transformer.transform_json_body(conf, json, transform_ops)
        local body_json = cjson.decode(body)
        assert.same(expected, body_json)
        assert.not_nil(err)
      end)

      it("can apply the function to json queries", function()
        -- this test showcases cool usage of this feature. Using arbitrary
        -- transforms we can apply functions that change the value without
        -- having to mess with type transformations, and that can apply
        -- changes cooperatively
        local transform_function = [[
          return function(data, key, value)
            if not value then return end
            data[key] = data[key] + tonumber(value)
          end
        ]]

        local yet_another_function = [[
          -- a function that does unexpected things
          return function(data, key)
            if data[key] and data[key] == 42 then
              data[key] = "hello world"
            end
          end

        ]]

        local json = [[
          {
            "some": "data",
            "foo": [{ "id": 1 }, { "id": 2 }, { "id": 3 }]
          }
        ]]

        local expected = {
          ["some"] = "data",
          ["foo"] = {
            { id = 41 },
            { id = "hello world" },
            { id = 43 },
          },
        }

        conf.transform.json = { "foo[*].id:40", "foo[*].id" }
        conf.transform.functions = { transform_function, yet_another_function }

        local transform_ops =  table.new(0, 7)
        transform_ops = body_transformer.determine_transform_operations(conf, 200, transform_ops)
        local body, err = body_transformer.transform_json_body(conf, json, transform_ops)
        local body_json = cjson.decode(body)
        assert.same(expected, body_json)
        assert.is_nil(err)
      end)

      it("does run README's example", function()
        local universe = [[
          -- universe.lua
          -- answers a question only when its known
          return function (data, key, value)
            if data[key] == value then
              data["a"] = 42
            end
          end
        ]]

        local json = [[
          {
            "questions": [
              { "q": "knock, knock" },
              { "q": "meaning of the universe" },
              { "q": "meaning of everything" }
            ]
          }
        ]]

        local expected = {
          questions = {
            { q = "knock, knock" },
            { q = "meaning of the universe", a = 42 },
            { q = "meaning of everything", a = 42 },
          }
        }

        conf.transform.json = {
          "questions[*].q:meaning of the universe",
          "questions[*].q:meaning of everything"
        }

        conf.transform.functions = { universe }

        local transform_ops =  table.new(0, 7)
        transform_ops = body_transformer.determine_transform_operations(conf, 200, transform_ops)
        local body, err = body_transformer.transform_json_body(conf, json, transform_ops)
        local body_json = cjson.decode(body)
        assert.same(expected, body_json)
        assert.is_nil(err)

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
        allow   = {
          json   = {}
        },
        transform = {
          functions = {},
          json   = {}
        },
      }

      it("skips all transforms whose response code don't match", function()
        local json = [[{"p1" : "v1", "p2" : "v1"}]]
        local transform_ops =  table.new(0, 7)
        transform_ops = body_transformer.determine_transform_operations(conf_skip, 200, transform_ops)
        local body = body_transformer.transform_json_body(conf_skip, json, transform_ops)
        local body_json = cjson.decode(body)
        assert.same({p1 = "v1", p2 = "v1"}, body_json)
      end)

      it("preserves empty array", function()
        local json = [[{"p1" : "v1", "p2" : "v1", "a" : []}]]

        -- status code matches
        local transform_ops =  table.new(0, 7)
        transform_ops = body_transformer.determine_transform_operations(conf_skip, 500, transform_ops)
        local body = body_transformer.transform_json_body(conf_skip, json, transform_ops)
        local body_json = cjson.decode(body)
        assert.same({p2 = "v2", p3 = {"v1", "v2"}, a = {}}, body_json)
        assert.equals('[]', cjson.encode(body_json.a))

        -- status code doesn't match
        local transform_ops =  table.new(0, 7)
        transform_ops = body_transformer.determine_transform_operations(conf_skip, 200, transform_ops)
        local body = body_transformer.transform_json_body(conf_skip, json, transform_ops)
        local body_json = cjson.decode(body)
        assert.same({p1 = "v1", p2 = "v1", a = {}}, body_json)
        assert.equals('[]', cjson.encode(body_json.a))
      end)
    end)
  end)

  describe("filter body", function()
    it("filter body if enabled without status code filter", function()
      local conf = {
        allow   = {
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
          json   = {},
          functions = {},
        },
      }
      local original_body = [[{"p1" : "v1", "p2" : "v1"}]]
      local transform_ops =  table.new(0, 7)
      transform_ops = body_transformer.determine_transform_operations(conf, 200, transform_ops)
      local body = body_transformer.transform_json_body(conf, original_body, transform_ops)
      assert.same([[{"p1":"v1"}]], body)
    end)
  end)

  describe("gzip", function()
    local old_ngx, handler
    local headers = {}

    setup(function()
      old_ngx  = ngx
      _G.ngx = {
        ctx = {
          buffers = {},
        },
      }
      _G.kong = {
        log = {
          debug = function() end,
          err = spy.new(function() end)
        },
        response = {
          get_header = function (header)
            return headers[header]
          end,
          get_raw_body = function()
            table.insert(ngx.ctx.buffers, ngx.arg[1])

            if not ngx.arg[2] then
              ngx.arg[1] = nil
            else
              ngx.arg[1] = table.concat(ngx.ctx.buffers)
            end

            return ngx.arg[1]
          end,
          set_raw_body = function(body)
            ngx.arg[1] = body
            ngx.arg[2] = true
          end,
        },
        table = table,
      }
      handler = require("kong.plugins.response-transformer-advanced.handler")
    end)

    teardown(function()
      -- luacheck: globals ngx
      ngx = old_ngx
    end)

    before_each(function()
      _G.ngx.ctx = {
        buffers = {},
      }
    end)

    it("valid gzip", function()
      local conf  = {
        remove    = {
          headers = {},
          json    = {}
        },
        add       = {
          headers = {},
          json    = { "p2:v2" },
        },
        append    = {
          headers = {},
          json    = {},
        },
        replace   = {
          headers = {},
          json    = {},
        },
        allow  = {
          json = {}
        },
        transform = {
          json = {},
          functions = {}
        },
      }

      local body = encode_base64(deflate_gzip(cjson.encode( { p1 = "v1" })))

      headers["Content-Type"] = "application/json"
      headers["Content-Encoding"] = "gzip"

      _G.ngx.arg = { decode_base64(body), false }
      handler:body_filter(conf)
      _G.ngx.arg = { "", true }
      handler:body_filter(conf)

      local result = cjson.decode(inflate_gzip(ngx.arg[1]))

      assert.same({ p2 = "v2", p1 = "v1"}, result)
    end)

    it("invalid gzip", function()
      local conf  = {
        remove    = {
          headers = {},
          json    = {}
        },
        add       = {
          headers = {},
          json    = { "p2:v2" },
        },
        append    = {
          headers = {},
          json    = {},
        },
        replace   = {
          headers = {},
          json    = {},
        },
        allow  = {
          json = {}
        },
        transform = {
          json = {},
          functions = {}
        },
      }

      -- Invalid gzip
      local body = "aaaabbbbcccc"

      headers["Content-Type"] = "application/json"
      headers["Content-Encoding"] = "gzip"

      _G.ngx.arg = { body, false }
      handler:body_filter(conf)
      _G.ngx.arg = { "", true }
      handler:body_filter(conf)

      local result = ngx.arg[1]

      assert.same("", result)
      assert.are.equal(500, ngx.status)
      assert.spy(kong.log.err).was.called()
    end)
  end)
end)
