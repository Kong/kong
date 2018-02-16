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


-- return migration for adding default workspace and existing
-- workspaceable entities to the default workspace
function _M.get_default_workspace_migration()
  return {
    default_workspace = {
      {
        name = "2018-02-16-110000_default_workspace_entities",
        up = function(_, _, dao)
          local default, err = dao.workspaces:insert({
            name = "default",
          })
          if err then
            return err
          end

          for relation, pk_name in pairs(workspaceable_relations) do
            local entities, err = dao[relation]:find_all()
            if err then
              return nil, err
            end

            for _, entity in ipairs(entities) do
              local relationship, err = dao.workspace_entities:insert({
                workspace_id = default.id,
                entity_id = entity.id,
                entity_type = relation,
              })
              if err then
                return nil, err
              end
            end
          end
        end,
      },
    }
  }
end


return _M
