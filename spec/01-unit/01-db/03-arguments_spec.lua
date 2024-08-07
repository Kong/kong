local Schema       = require "kong.db.schema"
local helpers      = require "spec.helpers"

local deep_sort = helpers.deep_sort

describe("arguments tests", function()

  local arguments, arguments_decoder, infer_value, infer, decode, combine, old_get_method
  local decode_arg, get_param_name_and_keys, nest_path, decode_map_array_arg

  lazy_setup(function()
    old_get_method = _G.ngx.req.get_method
    _G.ngx.req.get_method = function() return "POST" end

    package.loaded["kong.api.arguments"] = nil
    package.loaded["kong.api.arguments_decoder"] = nil

    arguments = require "kong.api.arguments"
    infer_value = arguments.infer_value
    decode      = arguments.decode
    infer       = arguments._infer
    combine     = arguments._combine

    arguments_decoder = require "kong.api.arguments_decoder"
    decode_arg = arguments_decoder._decode_arg
    get_param_name_and_keys = arguments_decoder._get_param_name_and_keys
    nest_path = arguments_decoder._nest_path
    decode_map_array_arg = arguments_decoder._decode_map_array_arg
  end)

  lazy_teardown(function()
    _G.ngx.req.get_method = old_get_method
  end)

  describe("arguments_decoder.infer_value", function()
    it("infers numbers", function()
      assert.equal(2, infer_value("2", { type = "number" }))
      assert.equal(2, infer_value("2", { type = "integer" }))
      assert.equal(2.5, infer_value("2.5", { type = "number" }))
      assert.equal(2.5, infer_value("2.5", { type = "integer" })) -- notice that integers are not rounded
    end)

    it("infers booleans", function()
      assert.equal(false, infer_value("false", { type = "boolean" }))
      assert.equal(true, infer_value("true", { type = "boolean" }))
    end)

    it("infers arrays and sets", function()
      assert.same({ "a" }, infer_value("a",   { type = "array", elements = { type = "string" } }))
      assert.same({ 2 },   infer_value("2",   { type = "array", elements = { type = "number" } }))
      assert.same({ "a" }, infer_value({"a"}, { type = "array", elements = { type = "string" } }))
      assert.same({ 2 },   infer_value({"2"}, { type = "array", elements = { type = "number" } }))

      assert.same({ "a" }, infer_value("a",   { type = "set", elements = { type = "string" } }))
      assert.same({ 2 },   infer_value("2",   { type = "set", elements = { type = "number" } }))
      assert.same({ "a" }, infer_value({"a"}, { type = "set", elements = { type = "string" } }))
      assert.same({ 2 },   infer_value({"2"}, { type = "set", elements = { type = "number" } }))
    end)

    it("infers nulls from empty strings", function()
      assert.equal(ngx.null, infer_value("", { type = "string" }))
      assert.equal(ngx.null, infer_value("", { type = "array" }))
      assert.equal(ngx.null, infer_value("", { type = "set" }))
      assert.equal(ngx.null, infer_value("", { type = "number" }))
      assert.equal(ngx.null, infer_value("", { type = "integer" }))
      assert.equal(ngx.null, infer_value("", { type = "boolean" }))
      assert.equal(ngx.null, infer_value("", { type = "foreign" }))
      assert.equal(ngx.null, infer_value("", { type = "map" }))
      assert.equal(ngx.null, infer_value("", { type = "record" }))
    end)

    it("doesn't infer nulls from empty strings on unknown types", function()
      assert.equal("", infer_value(""))
    end)

    it("infers maps", function()
      assert.same({ x = "1" }, infer_value({ x = "1" }, { type = "map", keys = { type = "string" }, values = { type = "string" } }))
      assert.same({ x = 1 },   infer_value({ x = "1" }, { type = "map", keys = { type = "string" }, values = { type = "number" } }))
    end)

    it("infers records", function()
      assert.same({ age = "1" }, infer_value({ age = "1" },
                                             { type = "record", fields = {{ age = { type = "string" } } }}))
      assert.same({ age = 1 },   infer_value({ age = "1" },
                                             { type = "record", fields = {{ age = { type = "number" } } }}))
    end)

    it("returns the provided value when inferring is not possible", function()
      assert.equal("not number", infer_value("not number", { type = "number" }))
      assert.equal("not integer", infer_value("not integer", { type = "integer" }))
      assert.equal("not boolean", infer_value("not boolean", { type = "boolean" }))
    end)
  end)


  describe("arguments_decoder.infer", function()
    it("returns nil for nil args", function()
      assert.is_nil(infer())
    end)

    it("does no inferring without schema", function()
      assert.same("args", infer("args"))
    end)

    it("infers every field using the schema", function()
      local schema = Schema.new({
        fields = {
          { name = { type = "string" } },
          { age  = { type = "number" } },
          { has_license = { type = "boolean" } },
          { aliases = { type = "set", elements = { type = { "string" } } } },
          { comments = { type = "string" } },
        }
      })

      local args = { name = "peter",
                     age = "45",
                     has_license = "true",
                     aliases = "peta",
                     comments = "" }
      assert.same({
        name = "peter",
        age = 45,
        has_license = true,
        aliases = { "peta" },
        comments = ngx.null
      }, infer(args, schema))
    end)

    it("infers shorthand_fields but does not run the func", function()
      local schema = Schema.new({
        fields = {
          { name = { type = "string" } },
          { another_array = { type = "array", elements = { type = { "string" } } } },
        },
        shorthand_fields = {
          { an_array = {
              type = "array",
              elements = { type = { "string" } },
              func = function(value)
                return { another_array = value:upper() }
              end,
            }
          },
        }
      })

      local args = { name = "peter",
                     an_array = "something" }
      assert.same({
        name = "peter",
        an_array = { "something" },
      }, infer(args, schema))
    end)

  end)

  describe("arguments_decoder.combine", function()
    it("merges arguments together, creating arrays when finding repeated names, recursively", function()
      local monster = {
        { a = { [99] = "wayne", }, },
        { a = { "first", }, },
        { a = { b = { c = { "true", }, }, }, },
        { a = { "a", "b", "c" }, },
        { a = { b = { c = { d = "" }, }, }, },
        { c = "test", },
        { a = { "1", "2", "3", }, },
      }

      local combined_monster = {
        a = {
          { "first", "a", "1" }, { "b", "2" }, { "c", "3" },
          [99] = "wayne",
          b = { c = { "true", d = "", }, }
        },
        c = "test",
      }

      assert.same(combined_monster, combine(monster))
    end)
  end)


  describe("arguments_decoder.decode_arg", function()
    it("does not infer numbers, booleans or nulls from strings", function()
      assert.same({ x = "" }, decode_arg("x", ""))
      assert.same({ x = "true" }, decode_arg("x", "true"))
      assert.same({ x = "false" }, decode_arg("x", "false"))
      assert.same({ x = "10" }, decode_arg("x", "10"))
    end)

    it("decodes arrays", function()
      assert.same({ x = { "a" } }, decode_arg("x[]", "a"))
      assert.same({ x = { "a" } }, decode_arg("x[1]", "a"))
      assert.same({ x = { nil, "a" } }, decode_arg("x[2]", "a"))
    end)

    it("decodes nested arrays", function()
      assert.same({ x = { { "a" } } }, decode_arg("x[1][1]", "a"))
      assert.same({ x = { nil, { "a" } } }, decode_arg("x[2][1]", "a"))
    end)
  end)

  describe("arguments_decoder.get_param_name_and_keys", function()
    it("extracts array keys", function()
      local name, _, keys, is_map = get_param_name_and_keys("foo[]")
      assert.equals(name, "foo")
      assert.same({ "" }, keys)
      assert.is_false(is_map)

      name, _, keys, is_map = get_param_name_and_keys("foo[1]")
      assert.same(name, "foo")
      assert.same({ "1" }, keys)
      assert.is_false(is_map)

      name, _, keys, is_map = get_param_name_and_keys("foo[1][2]")
      assert.same(name, "foo")
      assert.same({ "1", "2" }, keys)
      assert.is_false(is_map)
    end)

    it("extracts map keys", function()
      local name, _, keys, is_map = get_param_name_and_keys("foo[m]")
      assert.same(name, "foo")
      assert.same({ "m" }, keys)
      assert.is_true(is_map)

      name, _, keys, is_map = get_param_name_and_keys("[name][m][n]")
      assert.same(name, "[name]")
      assert.same({ "m", "n" }, keys)
      assert.is_true(is_map)
    end)

    it("extracts mixed map/array keys", function()
      local name, _, keys, is_map = get_param_name_and_keys("foo[].a")
      assert.same(name, "foo")
      assert.same({ "", "a" }, keys)
      assert.is_false(is_map)

      name, _, keys, is_map = get_param_name_and_keys("foo[1].a")
      assert.same(name, "foo")
      assert.same({ "1", "a" }, keys)
      assert.is_false(is_map)

      name, _, keys, is_map = get_param_name_and_keys("foo[1][2].a")
      assert.same(name, "foo")
      assert.same({ "1", "2", "a" }, keys)
      assert.is_false(is_map)

      name, _, keys, is_map = get_param_name_and_keys("foo.z[1].a[2].b")
      assert.same(name, "foo")
      assert.same({ "z", "1", "a", "2", "b" }, keys)
      assert.is_false(is_map)

      name, _, keys, is_map = get_param_name_and_keys("foo[m].a")
      assert.same(name, "foo")
      assert.same({ "m", "a" }, keys)
      assert.is_true(is_map)

      name, _, keys, is_map = get_param_name_and_keys("foo[m][n].a")
      assert.same(name, "foo")
      assert.same({ "m", "n", "a" }, keys)
      assert.is_true(is_map)

      name, _, keys, is_map = get_param_name_and_keys("foo[m].a[n].b")
      assert.same(name, "foo")
      assert.same({ "m", "a", "n", "b" }, keys)
      assert.is_true(is_map)

      name, _, keys, is_map = get_param_name_and_keys("foo[1][m].a")
      assert.same(name, "foo")
      assert.same({ "1", "m", "a" }, keys)
      assert.is_true(is_map)

      name, _, keys, is_map = get_param_name_and_keys("foo[m][1].a[n].b")
      assert.same(name, "foo")
      assert.same({ "m", "1", "a", "n", "b" }, keys)
      assert.is_true(is_map)
    end)
  end)

  describe("arguments_decoder.nest_path", function()
    it("nests simple value", function()
      local container = {}
      nest_path(container, { "foo" }, "a")
      assert.same({ foo = "a" }, container)
    end)

    it("nests arrays", function()
      local container = {}
      nest_path(container, { "foo", "1" }, "a")
      assert.same({ foo = { [1] = "a" } }, container)

      container = {}
      nest_path(container, { "foo", "1", "2" }, 12)
      assert.same({ foo = { [1] = { [2] = 12 } } }, container)

      container = {}
      nest_path(container, { "foo", "1", "2", "3" }, false)
      assert.same({ foo = { [1] = { [2] = { [3] = false } } } }, container)
    end)

    it("nests maps", function()
      local container = {}
      nest_path(container, { "foo", "bar" }, "a")
      assert.same({ foo = { bar = "a" } }, container)

      container = {}
      nest_path(container, { "foo", "bar", "baz" }, true)
      assert.same({ foo = { bar = { baz = true } } }, container)

      container = {}
      nest_path(container, { "foo", "bar", "baz", "qux" }, 42)
      assert.same({ foo = { bar = { baz = { qux = 42 } } } }, container)
    end)

    it("nests mixed map/array", function()
      local container = {}
      nest_path(container, { "foo", "1", "bar" }, "a")
      assert.same({ foo = { [1] = { bar = "a" } } }, container)

      container = {}
      nest_path(container, { 1, "1", "bar", "2" }, 42)
      assert.same({ [1] = { [1] = { bar = { [2] = 42 } } } }, container)
    end)
  end)

  describe("arguments_decoder.decode_map_array_arg", function()
    it("decodes arrays", function()
      local container = {}

      decode_map_array_arg("x[]", "a", container)
      assert.same({ x = { [1] = "a" } }, container)

      container = {}
      decode_map_array_arg("x[1]", "a", container)
      assert.same({ x = { [1] = "a" } }, container)

      container = {}
      decode_map_array_arg("x[1][2][3]", 42, container)
      assert.same({ x = { [1] = { [2] = { [3] = 42 } } } }, container)
    end)

    it("decodes maps", function()
      local container = {}

      decode_map_array_arg("x[a]", "a", container)
      assert.same({ x = { a = "a" } }, container)

      container = {}
      decode_map_array_arg("x[a][b][c]", 42, container)
      assert.same({ x = { a = { b = { c = 42 } } } }, container)
    end)

    it("decodes mixed map/array", function()
      local container = {}

      decode_map_array_arg("x[][a]", "a", container)
      assert.same({ x = { [1] = { a = "a" } } }, container)

      container = {}
      decode_map_array_arg("x[1][a]", "a", container)
      assert.same({ x = { [1] = { a = "a" } } }, container)

      container = {}
      decode_map_array_arg("x[1][2][a]", "a", container)
      assert.same({ x = { [1] = { [2] = { a = "a" } } } }, container)

      container = {}
      decode_map_array_arg("x[a][1][b]", "a", container)
      assert.same({ x = { a = { [1] = { b = "a" } } } }, container)

      container = {}
      decode_map_array_arg("x[a][1][b]", "a", container)
      assert.same({ x = { a = { [1] = { b = "a" } } } }, container)

      container = {}
      decode_map_array_arg("x[1][a][2][b]", "a", container)
      assert.same({ x = { [1] = { a = { [2] = { b = "a" } } } } }, container)

      container = {}
      decode_map_array_arg("x.r[1].s[a][2].t[b].u", "a", container)
      assert.same({ x = { r = { [1] = { s = { a = { [2] = { t = { b = { u = "a" } } } } } } } } }, container)
    end)
  end)

  describe("arguments_decoder.decode", function()

    it("decodes complex nested parameters", function()
      assert.same(deep_sort{
        c = "test",
        a = {
          {
            "first",
            "a",
            "1",
          },
          {
            "b",
            "2",
          },
          {
            "c",
            "3",
          },
          [99] = "wayne",
          b = {
            [1] = "x",
            [2] = "y",
            [3] = "z",
            [98] = "wayne",
            c = {
              "true",
              d = "",
              ["test.key"] = {
                "d",
                "e",
                "f",
              },
              ["escaped.k.2"] = {
                "d",
                "e",
                "f",
              }
            }
          },
          foo = "bar",
          escaped_k_1 = "bar",
        },
      },
      deep_sort(decode{
        ["a.b.c.d"]   = "",
        ["a"]         = { "1", "2", "3" },
        ["c"]         = "test",
        ["a.b.c"]     = { "true" },
        ["a[]"]       = { "a", "b", "c" },
        ["a[99]"]     = "wayne",
        ["a[1]"]      = "first",
        ["a[foo]"]    = "bar",
        ["a.b%5B%5D"]   = { "x", "y", "z" },
        ["a.b%5B98%5D"] = "wayne",
        ["a.b.c[test.key]"]        = { "d", "e", "f" },
        ["a%5Bescaped_k_1%5D"]     = "bar",
        ["a.b.c%5Bescaped.k.2%5D"] = { "d", "e", "f" },
      }))

      assert.same(deep_sort{
        a = {
          b = {
            c = {
              ["escaped.k.3"] = {
                "d",
                "e",
                "f",
              }
            }
          },
          escaped_k_1 = "bar",
          ESCAPED_K_2 = "baz",
          ["escaped%5B_k_4"] = "vvv",
          ["escaped.k_5"] = {
            nested = "ww",
          }
        },
      },
      deep_sort(decode{
        ["a%5Bescaped_k_1%5D"]        = "bar",
        ["a%5BESCAPED_K_2%5D"]        = "baz",
        ["a.b.c%5Bescaped.k.3%5D"]    = { "d", "e", "f" },
        ["a%5Bescaped%5B_k_4%5D"]     = "vvv",
        ["a%5Bescaped.k_5%5D.nested"] = "ww",
      }))
    end)

    it("decodes complex nested parameters combinations", function()
      assert.same({
        a = {
          {
            "a",
            cat = "tommy"
          },
          {
            "b1",
            "b2",
            dog = "jake"
          },
          {
            "c",
            cat = { "tommy", "the", "cat" },
          },
          {
            "d1",
            "d2",
            dog = { "jake", "the", "dog" }
          },
          {
            "e1",
            "e2",
            dog = { "finn", "the", "human" }
          },
          one = {
            "a",
            cat = "tommy"
          },
          two = {
            "b1",
            "b2",
            dog = "jake"
          },
          three = {
            "c",
            cat = { "tommy", "the", "cat" },
          },
          four = {
            "d1",
            "d2",
            dog = { "jake", "the", "dog" }
          },
          five = {
            "e1",
            "e2",
            dog = { "finn", "the", "human" }
          },
        }
      },
      decode{
        ["a[1]"] = "a",
        ["a[1].cat"] = "tommy",
        ["a[2]"] = { "b1", "b2" },
        ["a[2].dog"] = "jake",
        ["a[3]"] = "c",
        ["a[3].cat"] = { "tommy", "the", "cat" },
        ["a[4]"] = { "d1", "d2" },
        ["a[4].dog"] = { "jake", "the", "dog" },
        ["a%5B5%5D"] = { "e1", "e2" },
        ["a%5B5%5D.dog"] = { "finn", "the", "human" },
        ["a[one]"] = "a",
        ["a[one].cat"] = "tommy",
        ["a[two]"] = { "b1", "b2" },
        ["a[two].dog"] = "jake",
        ["a[three]"] = "c",
        ["a[three].cat"] = { "tommy", "the", "cat" },
        ["a[four]"] = { "d1", "d2" },
        ["a[four].dog"] = { "jake", "the", "dog" },
        ["a%5Bfive%5D"] = { "e1", "e2" },
        ["a%5Bfive%5D.dog"] = { "finn", "the", "human" },
      })
    end)

    it("decodes multidimensional arrays and maps", function()
      assert.same({
        key = {
          { "value" }
        }
      },
      decode{
        ["key[][]"] = "value",
      })

      assert.same({
        key = {
          [5] = { [4] = "value" }
        }
      },
      decode{
        ["key[5][4]"] = "value",
      })

      assert.same({
        key = {
          foo = { bar = "value" }
        }
      },
      decode{
        ["key[foo][bar]"] = "value",
      })

      assert.same({
        key = {
          [5] = { [4] = { key = "value" } }
        }
      },
      decode{
        ["key[5][4].key"] = "value",
      })

      assert.same({
        key = {
          [5] = { [4] = { key = "value" } }
        }
      },
      decode{
        ["key%5B5%5D%5B4%5D.key"] = "value",
      })

      assert.same({
        key = {
          foo = { bar = { key = "value" } }
        }
      },
      decode{
        ["key[foo][bar].key"] = "value",
      })

      assert.same({
        ["[5]"] = {{ [4] = { key = "value" } }}
      },
      decode{
        ["[5][1][4].key"] = "value"
      })

      assert.same({
        ["[5]"] = { foo = { bar = { key = "value" } }}
      },
      decode{
        ["[5][foo][bar].key"] = "value"
      })

      assert.same({
        key = {
          foo = { bar = { key = "value" } }
        }
      },
      decode{
        ["key%5Bfoo%5D%5Bbar%5D.key"] = "value",
      })
    end)

    pending("decodes different array representations", function()
      -- undefined:  the result depends on whether `["a"]` or `["a[2]"]` is applied first
      -- but there's no way to guarantee order without adding a "presort keys" step.
      -- but it's unlikely that a real-world client uses both forms in the same request,
      -- instead of making `decode()` slower, split test in two
      local decoded = decode{
        ["a"]    = { "1", "2" },
        ["a[]"]  = "3",
        ["a[1]"] = "4",
        ["a[2]"] = { "5", "6" },
      }

      assert.same(
        deep_sort{ a = {
            { "4", "1", "3" },
            { "5", "6", "2" },
          }
        },
        deep_sort(decoded)
      )
    end)

    it("decodes different array representations", function()
      -- same as previous test, but split to reduce ordering dependency
      assert.same(
        { a = {
          "2",
          { "1", "3", "4" },
          }
        },
        deep_sort(decode{
          ["a"]    = { "1", "2" },
          ["a[]"]  = "3",
          ["a[1]"] = "4",
        }))

      assert.same(
        { a = {
            { "3", "4" },
            { "5", "6" },
          }
        },
        deep_sort(decode{
          ["a[]"]  = "3",
          ["a[1]"] = "4",
          ["a[2]"] = { "5", "6" },
        }))
    end)

    it("infers values when provided with a schema", function()
      local schema = Schema.new({
        fields = {
          { name = { type = "string" } },
          { age  = { type = "number" } },
          { has_license = { type = "boolean" } },
          { aliases = { type = "set", elements = { type = { "string" } } } },
          { comments = { type = "string" } },
        }
      })

      local args = { name = "peter",
                     age = "45",
                     has_license = "true",
                     ["aliases[]"] = "peta",
                     comments = "" }
      assert.same({
        name = "peter",
        age = 45,
        has_license = true,
        aliases = { "peta" },
        comments = ngx.null
      }, decode(args, schema))
    end)
  end)
end)
