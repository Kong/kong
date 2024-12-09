local schema_topological_sort = require("kong.db.schema.topological_sort")
local from_chain = require("kong.db.resumable_chunker.chain").from_chain
local from_dao = require("kong.db.resumable_chunker.dao").from_dao
local inplace_merge = require("kong.db.resumable_chunker.utils").inplace_merge
local EMPTY = require("kong.tools.table").EMPTY


local _M = {}
local _MT = { __index = _M }

-- TODO: handling disabled entities
-- it may require a change to the dao or even the strategy (by filtering the rows when querying)
function _M.from_db(db, options)
  options = options or EMPTY
  local schemas, n = {}, 0

  local skip_ws = options.skip_ws

  for a, dao in pairs(db.daos) do
    local schema = dao.schema
    if schema.db_export ~= false and not (skip_ws and schema.name == "workspaces") then
      n = n + 1
      schemas[n] = schema
    end
  end

  local sorted_schemas, err = schema_topological_sort(schemas)
  if not sorted_schemas then
    return nil, err
  end

  local sorted_daos = {}
  for i, schema in ipairs(sorted_schemas) do
    sorted_daos[i] = db.daos[schema.name]
  end
  
  return _M.from_daos(sorted_daos, options)
end

function _M.from_daos(sorted_daos, options)
  options = options or EMPTY

  local chains, n = {}, 0
  for _, dao in ipairs(sorted_daos) do
    local chain = from_dao(dao, options)
    n = n + 1
    chains[n] = chain
  end

  return from_chain(chains, options)
end


return _M
