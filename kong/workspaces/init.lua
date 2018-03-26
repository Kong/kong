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


local function any(pred, t)
  local r = nil
  for _,v in ipairs(t) do
    r = pred(v)
    if r then return r end
  end
  return false
end


local function member(elem, t)
  return any(function(x) return x == elem end, t)
end


local function is_wildcard_host(host)
  return host:find("*") and true
end


local function is_wildcard(route)
  return any(is_wildcard_host, route.hosts)
end


local function listify(x)
  return (type(x) == "table") and x or {x}
end


local function is_blank(t)
  return not t or #t == 0
end


-- get the workspace name
-- if not in the context of a request, return '*', meaning all
-- workspaces
function _M.get_workspace()
  local r = getfenv(0).__ngx_req
  if not r then
    return  {
      name = "*"
    }
  else
    return ngx.ctx.workspace
  end
end


-- register a relation name and its primary key name as a workspaceable
-- relation
function _M.register_workspaceable_relation(relation, primary_keys, unique_keys)
  -- we explicitly take only the first component of the primary key - ie,
  -- in plugins, this means we only take the plugin ID
  if not workspaceable_relations[relation] then
    workspaceable_relations[relation] = {
      primary_key = primary_keys[1],
      unique_keys = unique_keys
    }
    return true
  end
  return false
end


function _M.get_workspaceable_relations()
  return setmetatable({}, metatable(workspaceable_relations))
end

local function add_entity_relation_db(dao, ws_id, entity_id, table_name, field_name, field_value)
  return dao:insert({
    workspace_id = ws_id,
    entity_id = entity_id,
    entity_type = table_name,
    unique_field_name = field_name or "",
    unique_field_value = field_value or "",
  })
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

          for relation, constraints in pairs(workspaceable_relations) do
            local entities, err = dao[relation]:find_all()
            if err then
              return nil, err
            end

            for _, entity in ipairs(entities) do
              if constraints.unique_keys then
                for k, _ in pairs(constraints.unique_keys) do
                  local _, err = add_entity_relation_db(dao.workspace_entities, default.id,
                                                        entity[constraints.primary_key],
                                                        relation, k, entity[k])
                  if err then
                    return nil, err
                  end
                end
              else
                local _, err = add_entity_relation_db(dao.workspace_entities, default.id,
                                                      entity[constraints.primary_key],
                                                      relation, constraints.primary_key,
                                                      entity[constraints.primary_key])
                if err then
                  return nil, err
                end
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


function _M.get_req_workspace(params)
  if params.workspace_name == "*" then
    return { name = "*" }
  else
    return retrieve_workspace(params.workspace_name)
  end
end


function _M.add_entity_relation(table_name, entity, workspace)
  local constraints = workspaceable_relations[table_name]
  if constraints.unique_keys then
    for k, _ in pairs(constraints.unique_keys) do
      local _, err = add_entity_relation_db(singletons.dao.workspace_entities, workspace.id,
                                            entity[constraints.primary_key],
                                            table_name, k, entity[k])
      if err then
        return err
      end
    end
    return
  end

  local _, err = add_entity_relation_db(singletons.dao.workspace_entities, workspace.id,
                                        entity[constraints.primary_key],
                                        table_name, constraints.primary_key,
                                        entity[constraints.primary_key])
  if err then
    return err
  end
end


function _M.delete_entity_relation(table_name, entity)
  local constraints = workspaceable_relations[table_name]
  if not constraints then
    return
  end

  local res, err = singletons.dao.workspace_entities:find_all({
    entity_id = entity[constraints.primary_key],
  })
  if err then
    return err
  end

  for _, row in ipairs(res) do
    local res, err = singletons.dao.workspace_entities:delete(row)
    if err then
      return err
    end
  end
end


function _M.update_entity_relation(table_name, entity)
  local constraints = workspaceable_relations[table_name]
  if constraints and constraints.unique_keys then
    for k, _ in pairs(constraints.unique_keys) do
      local res, err = singletons.dao.workspace_entities:find_all({
        entity_id = entity[constraints.primary_key],
        unique_field_name = k,
      })
      if err then
        return err
      end

      for _, row in ipairs(res) do
        local res , err = singletons.dao.workspace_entities:update({
          unique_field_value = entity[k]
        }, row)
      end
      if err then
        return err
      end
    end
  end
end


function _M.find_entity_by_unique_field(params)
  local rows, err = singletons.dao.workspace_entities:find_all(params)
  if err then
    return nil, err
  end
  if rows then
    return rows[1]
  end
end


function _M.match_route(router, method, uri, host)
  return router.select(method, uri, host)
end


function _M.api_in_ws(api, ws)
  return member(ws.name, listify(api.workspace))
end

function _M.validate_route_for_ws(router, method, uri, host, ws)

  local selected_route = _M.match_route(router, method, uri, host)

  if selected_route == nil then -- no match ,no conflict
    return true

  elseif _M.api_in_ws(selected_route, ws) then -- same workspace
    return true

  elseif is_blank(selected_route.api.hosts) then -- we match from a no-host route
    return true

  elseif is_wildcard(selected_route.api) then -- has host & it's wildcard
    -- we try to add a wildcard
    if host and is_wildcard_host(host) and member(host, selected_route.api.hosts) then -- ours is also wildcard
      return false
    else
      return true
    end

  elseif host ~= nil then       -- 2.c.ii.1.b
    return false

  else -- different ws, selected_route has host and candidate not
    return true
  end

end


return _M
