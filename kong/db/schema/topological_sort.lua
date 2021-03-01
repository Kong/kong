local constants = require "kong.constants"
local utils = require "kong.tools.utils"

local utils_toposort = utils.topological_sort


local sort_core_first do
  local CORE_SCORE = {}
  for _, v in ipairs(constants.CORE_ENTITIES) do
    CORE_SCORE[v] = 1
  end
  CORE_SCORE["workspaces"] = 2

  sort_core_first = function(a, b)
    local sa = CORE_SCORE[a.name] or 0
    local sb = CORE_SCORE[b.name] or 0
    if sa == sb then
      -- reverse alphabetical order, so that items end up ordered alphabetically
      -- (utils_toposort does "neighbors" before doing "current")
      return a.name > b.name
    end
    return sa < sb
  end
end


-- Given an array of schemas, return a copy of it sorted so that:
--
-- * If schema B has a foreign key to A, then B appears after A
-- * When there's no foreign keys, core schemas appear before plugin entities
-- * If none of the rules above apply, schemas are sorted alphabetically by name
--
-- The function returns an error if cycles are found in the schemas
-- (i.e. A has a foreign key to B and B to A)
--
-- @tparam array schemas an array with zero or more schemas
-- @treturn array|nil an array of schemas sorted topologically, or nil if cycle was found
-- @treturn nil|string nil if the schemas were sorted, or a message if a cycle was found
-- @usage
-- local res = topological_sort({ services, routes, plugins, consumers })
-- assert.same({ consumers, services, routes, plugins }, res)
local declarative_topological_sort = function(schemas)
  local s
  local schemas_by_name = {}
  local copy = {}

  for i = 1, #schemas do
    s = schemas[i]
    schemas_by_name[s.name] = s
    copy[i] = schemas[i]
  end
  schemas = copy

  table.sort(schemas, sort_core_first)

  -- given a schema, return all the schemas to which it has references
  -- (and are in the list of the `schemas` provided)
  local get_schema_neighbors = function(schema)
    local neighbors = {}
    local neighbors_len = 0
    local neighbor

    for _, field in schema:each_field() do
      if field.type == "foreign"  then
        neighbor = schemas_by_name[field.reference] -- services
        if neighbor then
          neighbors_len = neighbors_len + 1
          neighbors[neighbors_len] = neighbor
        end
        -- else the neighbor points to an unknown/uninteresting schema. This happens in tests.
      end
    end

    return neighbors
  end

  return utils_toposort(schemas, get_schema_neighbors)
end

return declarative_topological_sort
