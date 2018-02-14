local _M = {}


-- a map of workspaceable relations to its primary key name
local workspaceable_relations = {}


local function metatable(base)
  return {
    __index = base,
    __newindex = function()
      error "immutable table"
    end,
    __pairs = function()
      return next, base, nil
    end,
    __metatable = false,
  }
end


-- register a relation name and its primary key name as a workspaceable
-- relation
function _M.register_workspaceable_relation(relation, primary_key)
  -- we explicitly take only the first component of the primary key - ie,
  -- in plugins, this means we only take the plugin ID
  if not workspaceable_relations[relation] then
    workspaceable_relations[relation] = primary_key[1]
    return true
  end
  return false
end


function _M.get_workspaceable_relations()
  return setmetatable({}, metatable(workspaceable_relations))
end


return _M
