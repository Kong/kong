local arguments    = require "kong.api.arguments"
local Schema       = require "kong.db.schema"

local infer_value = arguments.infer_value
local infer       = arguments.infer
local decode_arg  = arguments.decode_arg
local decode      = arguments.decode
local combine     = arguments.combine


describe("arguments.infer_value", function()
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


describe("arguments.infer", function()
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
end)

describe("arguments.combine", function()
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


describe("arguments.decode_arg", function()
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

describe("arguments.decode", function()

  it("decodes complex nested parameters", function()
    assert.same({
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
          c = {
            "true",
            d = ""
          }
        }
      },
    },
    decode{
      ["a.b.c.d"] = "",
      ["a"]       = { "1", "2", "3" },
      ["c"]       = "test",
      ["a.b.c"]   = { "true" },
      ["a[]"]     = { "a", "b", "c" },
      ["a[99]"]   = "wayne",
      ["a[1]"]    = "first",
    })
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
        }
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
    })
  end)

  it("decodes multidimensional arrays", function()
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
        [5] = { [4] = { key = "value" } }
      }
    },
    decode{
      ["key[5][4].key"] = "value",
    })

    assert.same({
      ["[5]"] = {{ [4] = { key = "value" } }}
    },
    decode{
      ["[5][1][4].key"] = "value"
    })
  end)

  it("decodes different array representations", function()
    local decoded = decode{
      ["a"]    = { "1", "2" },
      ["a[]"]  = "3",
      ["a[1]"] = "4",
      ["a[2]"] = { "5", "6" },
    }

    assert.same(
      { a = {
          { "4", "1", "3" },
          { "5", "6", "2" },
        }
      },
      decoded
    )
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
