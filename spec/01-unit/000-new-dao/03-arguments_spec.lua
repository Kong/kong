local arguments    = require "kong.api.arguments"


local decode_value = arguments.decode_value
local decode       = arguments.decode
local tonumber     = tonumber
local null         = ngx.null


describe("arguments.decode_value", function()
  it("infers empty strings", function()
    assert.equal(null, decode_value(""))
  end)

  it("infers booleans", function()
    assert.equal(true, decode_value("true"))
    assert.equal(false, decode_value("false"))
  end)

  it("infers numbers", function()
    assert.equal(tonumber("123"), decode_value("123"))
    assert.equal(tonumber("0.1"), decode_value("0.1"))
  end)

  it("infers arrays", function()
    assert.same(
      { null, true, false, tonumber("123"), tonumber("0.1") },
      decode_value { "", "true", "false", "123", "0.1" }
    )
  end)
end)


describe("arguments.decode", function()
  it("decodes empty strings", function()
    assert.same({ name = decode_value("") }, decode{ name = "" })
  end)

  it("decodes booleans", function()
    assert.same({ name = decode_value("true") }, decode{ name = "true" })
    assert.same({ name = decode_value("false") }, decode{ name = "false" })
  end)

  it("decodes numbers", function()
    assert.same({ name = decode_value("123") }, decode{ name = "123" })
    assert.same({ name = decode_value("0.1") }, decode{ name = "0.1" })
  end)

  it("decodes arrays", function()
    assert.same(
      { name = { decode_value(""), decode_value("true"), decode_value("false"), decode_value("123"), decode_value("0.1") }},
      decode { name = { "", "true", "false", "123", "0.1" } }
    )
  end)

  it("decodes object", function()
    assert.same({ service = { name = decode_value("") }},              decode{ ["service.name"] = "" })
    assert.same({ service = { name = decode_value("true") }},          decode{ ["service.name"] = "true" })
    assert.same({ service = { name = decode_value("false") }},         decode{ ["service.name"] = "false" })
    assert.same({ service = { name = decode_value("123") }},           decode{ ["service.name"] = "123" })
    assert.same({ service = { name = decode_value("0.1") }},           decode{ ["service.name"] = "0.1" })
    assert.same({ service = { name = decode_value("true"),  id = 1 }}, decode{ ["service.name"] = "true",  ["service.id"] = "1" })
    assert.same({ service = { name = decode_value("false"), id = 1 }}, decode{ ["service.name"] = "false", ["service.id"] = "1" })
    assert.same({ service = { name = decode_value("123"),   id = 1 }}, decode{ ["service.name"] = "123",   ["service.id"] = "1" })
    assert.same({ service = { name = decode_value("0.1"),   id = 1 }}, decode{ ["service.name"] = "0.1",   ["service.id"] = "1" })
  end)

  it("decodes array and object parts", function()
    assert.same(
      { service = { name = { decode_value(""), decode_value("true"), decode_value("false"), decode_value("123"), decode_value("0.1") }}},
      decode { ["service.name"] = { "", "true", "false", "123", "0.1" } }
    )
    assert.same(
      { service = { name = { decode_value(""), decode_value("true"), decode_value("false"), decode_value("123"), decode_value("0.1") }, id = 1 }},
      decode { ["service.name"] = { "", "true", "false", "123", "0.1" }, ["service.id"] = 1 }
    )

    assert.same(
      { service = { decode_value(""), decode_value("true"), decode_value("false"), decode_value("123"), decode_value("0.1"), id = 1 }},
      decode { ["service[]"] = { "", "true", "false", "123", "0.1" }, ["service.id"] = "1" }
    )
  end)

  it("decodes complex nested parameters", function()
    assert.same({
      c = "test",
      a = {
        {
          "first",
          "a",
          1,
        },
        {
          "b",
          2,
        },
        {
          "c",
          3,
        },
        [99] = "wayne",
        b = {
          c = {
            true,
            d = null
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

    assert.is_table(decoded.a[1])
    assert.equal(3, #decoded.a[1])

    local f1 = {
      [1] = false,
      [3] = false,
      [4] = false,
    }

    for _, v in ipairs(decoded.a[1]) do
      f1[v] = true
    end

    for _, ok in pairs(f1) do
      assert.is_true(ok)
    end

    local f2 = {
      [2] = false,
      [5] = false,
      [6] = false,
    }

    for _, v in ipairs(decoded.a[2]) do
      f2[v] = true
    end

    for _, ok in pairs(f2) do
      assert.is_true(ok)
    end

    assert.is_table(decoded.a[2])
    assert.equal(3, #decoded.a[2])
  end)
end)
