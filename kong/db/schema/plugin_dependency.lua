-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


--- Adds a dependency relationship between two items in a given dependencies table.
-- If the item doesn't already have a dependencies list in the table, this function initializes it as an empty list.
-- The dependency relationship is added as an edge from the item to the depends_on item.
-- @param dependencies (table) - A table where keys are items and values are lists of items that the key item depends on.
-- @param item - The item that depends on another item (the source node of the edge).
-- @param depends_on - The item that the first item depends on (the destination node of the edge).
local function add_dependency(dependencies, item, depends_on)
  -- Check if the item already has a list of dependencies in the table.
  -- If not, initialize an empty list.
  if not dependencies[item] then
    dependencies[item] = {}
  end

  -- Add the depends_on item to the list of dependencies for the item.
  table.insert(dependencies[item], depends_on)
end


--- Performs a topological sort on a directed acyclic graph (DAG) represented by a set of items and their dependencies.
-- The function returns a list of items in topologically sorted order, such that for every directed edge (u, v), node u comes before v in the ordering.
-- If the graph has a cycle, the function returns an error message.
-- @param items (table) - A list of items (nodes) in the graph.
-- @param dependencies (table) - A table where keys are items and values are lists of items that the key item depends on.
-- @return sorted (table) - A list of items in topologically sorted order.
-- @return errMsg (string) - An error message if there's a cycle in the graph, nil otherwise.
local function topological_sort(items, dependencies)
  local sorted = {}         -- Stores the sorted items
  local visited = {}        -- Tracks visited items
  local path = {}           -- Tracks the current path in the traversal
  local has_cycle = false   -- Indicates whether a cycle is detected

  --- Helper function for depth-first traversal
  -- Marks the item as visited, adds it to the path, and recursively visits its dependencies.
  -- If a cycle is detected, the hasCycle flag is set.
  -- @param item - The item to visit.
  local function visit(item)
    if visited[item] then
      return
    end

    visited[item] = true
    path[item] = true     -- Add the item to the current path

    local item_dependency = dependencies[item] or {}
    for i = 1, #item_dependency do
      local depends_on = item_dependency[i]
      if path[depends_on] then
        has_cycle = true         -- Cycle detected
        return
      end
      visit(depends_on)
    end

    -- Remove the item from the current path
    -- By removing the item from the path, the algorithm
    -- ensures that when it backtracks, it doesn't incorrectly
    -- identify a cycle when encountering the same item again in
    -- another branch of the traversal. This step is crucial for
    -- correctly detecting cycles in the graph and ensuring the
    -- validity of the topological sort.
    path[item] = nil
    table.insert(sorted, item)
  end

  -- Perform depth-first traversal on each item
  for _, item in ipairs(items) do
    visit(item)
    if has_cycle then
      return nil, "There is a circular dependency in the graph. It is not possible to derive a topological sort."
    end
  end


  return sorted
end



return {
  add = add_dependency,
  sort = topological_sort
}
