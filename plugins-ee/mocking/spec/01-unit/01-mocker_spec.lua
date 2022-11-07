-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local mocker = require("kong.plugins.mocking.jsonschema-mocker.mocker")
local pl_tablex = require("pl.tablex")

local m = mocker.mock

local function structure_like(source, target)
  for k, v in pairs(source) do
    local source_type = type(v)
    local target_value = target[k]
    if source_type ~= type(target_value) then
      return false, string.format("%s(%s) and %s(%s) are not the same type", v, source_type, target_value, type(target_value))
    end
    if source_type == "table" then
      local ok, err = structure_like(v, target_value)
      if not ok then
        return false, err
      end
    end
  end
  return true, nil
end


describe("jsonschema mocker", function()

  it("value type", function()
    assert.equal("boolean", type(m({ type = "boolean" })))
    assert.equal("number", type(m({ type = "integer" })))
    assert.equal("number", type(m({ type = "number" })))
    assert.equal("string", type(m({ type = "string" })))
    assert.equal("table", type(m({ type = "array" })))
    assert.equal("table", type(m({ type = "object" })))
  end)

  it("enum", function()
    local tests = {
      boolean = { false, true },
      integer = { 1, 2, 3 },
      number = { 1.1, 1.3, 1.4 },
      string = { "ASC", "DESC" },
      object = { { id = 1 }, { id = 2 }, { id = 3 } },
      array = { { 'a', 'b' }, { 'c', 'd' }, { 'e', 'f' } }
    }
    for t, enum in pairs(tests) do
      local v = m({ type = t, enum = enum })
      local match = false
      for _, e in ipairs(enum) do
        match = pl_tablex.deepcompare(v, e)
        if match then
          break
        end
      end
      assert.is_true(match)
    end
  end)

  it("boolean", function()
    assert.equal(false, m({ type = "boolean", example = false }))
    assert.equal(true, m({ type = "boolean", example = true }))
    assert.equal("boolean", type(m({ type = "boolean", example = "string" })))
  end)

  it("integer", function()
    assert.equal(0, m({ type = "integer", example = 0 }))
    assert.equal(999, m({ type = "integer", example = 999.99 }))
    assert.equal(1, m({ type = "integer", minimum = 0, maximum = 1, exclusiveMinimum = true }))
    assert.equal(0, m({ type = "integer", minimum = 0, maximum = 1, exclusiveMaximum = true }))
    local v = m({ type = "integer", minimum = 0, maximum = 1 })
    assert.is_true(v >= 0 and v <= 1)
  end)

  it("number", function()
    assert.equal(0, m({ type = "number", example = 0 }))
    assert.equal(999.99, m({ type = "number", example = 999.99 }))
    local v = m({ type = "number", minimum = 9, maximum = 10 })
    assert.is_true(v >= 9 and v <= 10)
  end)

  it("string", function()
    assert.equal("", m({ type = "string", example = "" }))
    assert.equal("The example", m({ type = "string", example = "The example" }))
    local v = m({ type = "string", minLength = 1, maxLength = 3 })
    assert.is_true(#v >= 1 and #v <= 3)

    -- format
    assert.truthy(string.match(m({ type = "string", format = "date" }), "^%d+%-%d%d%-%d%d$"))
    assert.truthy(string.match(m({ type = "string", format = "date-time" }), "^%d+%-%d%d%-%d%dT%d%d:%d%d:%d%dZ$"))
  end)

  it("array", function()
    assert.same({}, m({ type = "array" }))
    assert.same({ 1, 2, 3 }, m({ type = "array", example = { 1, 2, 3 } }))

    for _, t in ipairs({ "boolean", "integer", "number", "string" }) do
      local value = m({ type = "array", items = { type = t }, minItems = 1, maxItems = 10 })
      assert.is_true(type(value) == "table")
      assert.is_true(#value >= 1 and #value <= 10)
      for _, v in ipairs(value) do
        if t == "integer" then
          t = "number"
        end
        assert.equal(t, type(v))
      end
    end

    for _, t in ipairs({ "boolean", "integer", "number", "string" }) do
      local length = 2
      local value = m({
        type = "array",
        items = {
          type = "array",
          items = {
            type = t
          },
          minItems = length,
          maxItems = length,
        },
        minItems = 1,
        maxItems = 10,
      })
      assert.is_true(type(value) == "table")
      assert.is_true(#value >= 1 and #value <= 10)
      for _, array in ipairs(value) do
        for _, v in ipairs(array) do
          if t == "integer" then
            t = "number"
          end
          assert.equal(t, type(v))
        end
        assert.equal(length, #array)
      end
    end

    local v = m({
      allOf = {
        {
          type = "object",
          properties = {
            code = { type = "string" },
            msg = { type = "string" }
          }
        },
        {
          type = "object",
          properties = {
            data = {
              type = "object",
              properties = {
                id = { type = "integer" },
                name = { type = "string" }
              }
            }
          }
        }
      }
    })
    --debug(v)

    local ok, err = structure_like({
      code = "",
      data = {
        id = 0,
        name = ""
      },
      msg = ""
    }, v)
    assert.is_nil(err)
    assert.is_true(ok)

    local v = m({
      type = "array",
      minItems = 2,
      maxItems = 2,
      items = {
        type = "object",
        properties = {
          id = { type = "integer" },
          profile = {
            allOf = {
              {
                type = "object",
                properties = { avatar = { type = "string" } }
              },
              {
                type = "object",
                properties = { resume = { type = "string" } }
              }
            }
          }
        }
      }
    })

    local ok, err = structure_like({
      {
        id = 9738,
        profile = {
          avatar = "wiZy5z",
          resume = "daiizMs3tL0piBgVd"
        }
      },
      {
        id = 1191,
        profile = {
          avatar = "SBKdZ",
          resume = ""
        }
      }
    }, v)
    assert.is_nil(err)
    assert.is_true(ok)
  end)

end)
