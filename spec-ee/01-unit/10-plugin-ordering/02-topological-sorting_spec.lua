-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local dependency_tracker = require "kong.db.schema.plugin_dependency"

describe("Topological sort and addDependency", function()
  local dependencies

  before_each(function()
    dependencies = {}
  end)

  describe("addDependency", function()
    it("adds a dependency to an empty list", function()
      dependency_tracker.add(dependencies, "A", "B")
      assert.same(dependencies, { ["A"] = { "B" } })
    end)

    it("adds multiple dependencies to the same item", function()
      dependency_tracker.add(dependencies, "A", "B")
      dependency_tracker.add(dependencies, "A", "C")
      assert.same(dependencies, { ["A"] = { "B", "C" } })
    end)

    it("adds dependencies to multiple items", function()
      dependency_tracker.add(dependencies, "A", "B")
      dependency_tracker.add(dependencies, "C", "D")
      assert.same(dependencies, { ["A"] = { "B" },["C"] = { "D" } })
    end)
  end)

  describe("Topological Sorting for (DAG) Directed Acyclic Graphs", function()
    it("sorts items with no dependencies", function()
      -- A  B  C  D
      local items = { "A", "B", "C", "D" }
      local sorted, err = dependency_tracker.sort(items, dependencies)
      assert.is_nil(err)
      assert.same(sorted, items)
    end)

    it("sorts items with dependencies that do not change the order", function()
      --[[
                A --> B --> C
                |
                v
                D
            --]]
      local items = { "A", "B", "C", "D" }
      dependency_tracker.add(dependencies, "A", "B")
      dependency_tracker.add(dependencies, "B", "C")
      local sorted, err = dependency_tracker.sort(items, dependencies)
      assert.is_nil(err)
      assert.same({ "C", "B", "A", "D" }, sorted)
    end)

    it("returns an error for a circular dependency", function()
      --[[
                A --> B --> C
                ^           |
                |           v
                +-----------D
            --]]
      local items = { "A", "B", "C", "D" }
      dependency_tracker.add(dependencies, "A", "B")
      dependency_tracker.add(dependencies, "B", "C")
      dependency_tracker.add(dependencies, "C", "A")
      local sorted, err = dependency_tracker.sort(items, dependencies)
      assert.is_nil(sorted)
      assert.is_string(err)
    end)

    it("sorts items with multiple dependencies", function()
      --[[
                  A   B     E
                  \ /     /
                   C     F
                   \   /
                   D-G
            --]]
      local items = { "A", "B", "C", "D", "E", "F", "G" }
      dependency_tracker.add(dependencies, "A", "C")
      dependency_tracker.add(dependencies, "B", "C")
      dependency_tracker.add(dependencies, "C", "D")
      dependency_tracker.add(dependencies, "E", "F")
      dependency_tracker.add(dependencies, "F", "G")
      local sorted, err = dependency_tracker.sort(items, dependencies)
      assert.is_nil(err)
      assert.same({ "D", "C", "A", "B", "G", "F", "E" }, sorted)
    end)

    it("sorts items with multiple dependencies and disconnected subgraphs", function()
      --[[
                  A     E     H
                  |     |     |
                  B     F     I
                  |     |
                  C     G
                  |
                  D
            --]]
      local items = { "A", "B", "C", "D", "E", "F", "G", "H", "I" }
      dependency_tracker.add(dependencies, "A", "B")
      dependency_tracker.add(dependencies, "B", "C")
      dependency_tracker.add(dependencies, "C", "D")
      dependency_tracker.add(dependencies, "E", "F")
      dependency_tracker.add(dependencies, "F", "G")
      dependency_tracker.add(dependencies, "H", "I")
      local sorted, err = dependency_tracker.sort(items, dependencies)
      assert.is_nil(err)
      assert.same({ "D", "C", "B", "A", "G", "F", "E", "I", "H" }, sorted)
    end)

    it("returns an error for a complex circular dependency", function()
      --[[
                  A --> B     E
                  ^     |     |
                  |     v     v
                  D <-- C     F
                               \
                                G
            --]]
      local items = { "A", "B", "C", "D", "E", "F", "G" }
      dependency_tracker.add(dependencies, "A", "B")
      dependency_tracker.add(dependencies, "B", "C")
      dependency_tracker.add(dependencies, "C", "D")
      dependency_tracker.add(dependencies, "D", "A")
      dependency_tracker.add(dependencies, "E", "F")
      dependency_tracker.add(dependencies, "F", "G")
      local sorted, err = dependency_tracker.sort(items, dependencies)
      assert.is_nil(sorted)
      assert.is_string(err)
    end)
  end)
end)
