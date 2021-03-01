local Schema = require "kong.db.schema"
local ts = require "kong.db.schema.topological_sort"

describe("schemas_topological_sort", function()

  local function collect_names(schemas)
    local names = {}
    for i = 1, #schemas do
      names[i] = schemas[i].name
    end
    return names
  end

  local function schema_new(s)
    return assert(Schema.new(s))
  end

  it("sorts an array of unrelated schemas alphabetically by name", function()
    local a = schema_new({ name = "a", fields = {} })
    local b = schema_new({ name = "b", fields = {} })
    local c = schema_new({ name = "c", fields = {} })

    local x = ts({ c, a, b })
    assert.same({"a", "b", "c"},  collect_names(x))
  end)

  it("it puts destinations first", function()
    local a = schema_new({ name = "a", fields = {} })
    local c = schema_new({
      name = "c",
      fields = {
        { a = { type = "foreign", reference = "a" }, },
      }
    })
    local b = schema_new({
      name = "b",
      fields = {
        { a = { type = "foreign", reference = "a" }, },
        { c = { type = "foreign", reference = "c" }, },
      }
    })

    local x = ts({ a, b, c })
    assert.same({"a", "c", "b"},  collect_names(x))
  end)

  it("puts core entities first, even when no relations", function()
    local a = schema_new({ name = "a", fields = {} })
    local routes = schema_new({ name = "routes", fields = {} })

    local x = ts({ a, routes })
    assert.same({"routes", "a"},  collect_names(x))
  end)

  it("puts workspaces before core and others, when no relations", function()
    local a = schema_new({ name = "a", fields = {} })
    local workspaces = schema_new({ name = "workspaces", fields = {} })
    local routes = schema_new({ name = "routes", fields = {} })

    local x = ts({ a, routes, workspaces })
    assert.same({"workspaces", "routes", "a"},  collect_names(x))
  end)

  it("puts workspaces first, core entities second, and other entities afterwards, even with relations", function()
    local a = schema_new({ name = "a", fields = {} })
    local services = schema_new({ name = "services", fields = {} })
    local b = schema_new({
      name = "b",
      fields = {
        { service = { type = "foreign", reference = "services" }, },
        { a = { type = "foreign", reference = "a" }, },
      }
    })
    local routes = schema_new({
      name = "routes",
      fields = {
        { service = { type = "foreign", reference = "services" }, },
      }
    })
    local workspaces = schema_new({ name = "workspaces", fields = {} })
    local x = ts({ services, b, a, workspaces, routes })
    assert.same({ "workspaces", "services", "routes", "a", "b" },  collect_names(x))
  end)

  it("overrides core order if dependencies force it", function()
    -- This scenario is here in case in the future we allow plugin entities to precede core entities
    -- Not applicable today (kong 2.3.x) but maybe in future releases
    local a = schema_new({ name = "a", fields = {} })
    local services = schema_new({ name = "services", fields = {
      { a = { type = "foreign", reference = "a" } } -- we somehow forced services to depend on a
    }})
    local workspaces = schema_new({ name = "workspaces", fields = {
      { a = { type = "foreign", reference = "a" } } -- we somehow forced workspaces to depend on a
    } })

    local x = ts({ services, a, workspaces })
    assert.same({ "a", "workspaces", "services" },  collect_names(x))
  end)

  it("returns an error if cycles are found", function()
    local a = schema_new({
      name = "a",
      fields = {
        { b = { type = "foreign", reference = "b" }, },
      }
    })
    local b = schema_new({
      name = "b",
      fields = {
        { a = { type = "foreign", reference = "a" }, },
      }
    })
    local x, err = ts({ a, b })
    assert.is_nil(x)
    assert.equals("Cycle detected, cannot sort topologically", err)
  end)
end)
