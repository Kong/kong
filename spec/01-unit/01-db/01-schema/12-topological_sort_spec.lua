local Schema = require "kong.db.schema"
local ts = require "kong.db.schema.topological_sort"


local function collect_names(schemas)
  local names = {}
  for i = 1, #schemas do
    names[i] = schemas[i].name
  end
  return names
end

describe("topological_sort", function()

  it("sorts an array of unrelated schemas", function()
    local a = Schema.new({ name = "a", fields = { { a = { type = "string" } } } })
    local b = Schema.new({ name = "b", fields = { { b = { type = "boolean" } } } })
    local c = Schema.new({ name = "c", fields = { { c = { type = "integer" } } } })

    local x = ts({ a, b, c })
    assert.same({"c", "b", "a"},  collect_names(x))
  end)

  it("it puts destinations first", function()
    local a = Schema.new({ name = "a", fields = { { a = { type = "string" } } } })
    local c = Schema.new({
      name = "c",
      fields = {
        { c = { type = "integer" }, },
        { a = { type = "foreign", reference = "a" }, },
      }
    })
    local b = Schema.new({
      name = "b",
      fields = {
        { b = { type = "boolean" }, },
        { a = { type = "foreign", reference = "a" }, },
        { c = { type = "foreign", reference = "c" }, },
      }
    })

    local x = ts({ a, b, c })
    assert.same({"a", "c", "b"},  collect_names(x))
  end)

  it("returns an error if cycles are found", function()
    local a = Schema.new({
      name = "a",
      fields = {
        { a = { type = "string" }, },
        { b = { type = "foreign", reference = "b" }, },
      }
    })
    local b = Schema.new({
      name = "b",
      fields = {
        { b = { type = "boolean" }, },
        { a = { type = "foreign", reference = "a" }, },
      }
    })
    local x, err = ts({ a, b })
    assert.is_nil(x)
    assert.equals("Cycle detected, cannot sort topologically", err)
  end)
end)
