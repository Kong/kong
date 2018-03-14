local singletons = require "kong.singletons"
local utils      = require "kong.tools.utils"


local _M = {}

local default_workspace = "default"
_M.DEFAULT_WORKSPACE = default_workspace


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
            name = default_workspace,
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


local function retrieve_workspace(workspace_name)
  workspace_name = workspace_name or _M.DEFAULT_WORKSPACE

  local rows, err = singletons.dao.workspaces:find_all({
    name = workspace_name
  })
  if err then
    return nil, err
  end

  if err then
    log(ngx.ERR, "error in retrieving workspace: ", err)
    return nil, err
  end

  if not rows or #rows == 0 then
    return nil
  end

  return rows[1]
end


function _M.get_workspace(params)
  if params.workspace_name == "*" then
    return { name = "*" }
  else
    return retrieve_workspace(params.workspace_name)
  end
end


function _M.add_entity_relation(dao_collection, entity, workspace)
  local rel, err
  local primary_key = workspaceable_relations[dao_collection.table]
  if primary_key then
    rel, err = singletons.dao.workspace_entities:insert({
      workspace_id = workspace.id,
      entity_id = entity[primary_key],
      entity_type = dao_collection.table == "workspaces" and "workspace"
                    or dao_collection.table
    })
  end

  return rel, err
end


function _M.delete_entity_relation(ws, dao_collection, entity)
  local res, err
  local primary_key = workspaceable_relations[dao_collection.table]
  if primary_key then
    res, err = singletons.dao.workspace_entities:delete({
      entity_id = entity[primary_key],
      workspace_id = ws.id
    })
  end

  return res, err
end


return _M
