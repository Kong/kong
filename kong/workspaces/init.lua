local singletons = require "kong.singletons"
local utils      = require "kong.tools.utils"
local tablex = require "pl.tablex"
local cjson = require "cjson"


local find    = string.find
local format  = string.format
local ngx_log = ngx.log
local DEBUG   = ngx.DEBUG
local next    = next
local values = tablex.values
local cache = singletons.cache


local _M = {}

local default_workspace = "default"
_M.DEFAULT_WORKSPACE = default_workspace
local ALL_METHODS = "GET,POST,PUT,DELETE,OPTIONS,PATCH"


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


local function map(f, t)
  local r = {}
  local n = 0
  for _, x in ipairs(t) do
    n = n + 1
    r[n] = f(x)
  end
  return r
end

local function map_unique(f, t)
  local r = {}
  local unique = {}
  local n = 0
  for _, x in ipairs(t) do
    if not unique[x.workspace_id] then
      n = n + 1
      r[n] = f(x)
      unique[x.workspace_id] = true
    end
  end
  return r
end


-- helper function for permutations
local function inc(t, pos)
  if t[pos][2] == #t[pos][1] then
    if pos == 1 then
      return nil
    end

    t[pos][2] = 1
    return inc(t, pos-1)

  else
    t[pos][2] = t[pos][2] + 1
    return true
  end
end


-- returns a permutations iterator using the "odometer" algorithm.
-- Example usage:
-- for i in permutations({1,2} , {3,4}) do
--   print(i[1], i[2])
-- end
local function permutations(...)

  local sets = {...}
  -- create tuples of {elements, curr_pos}
  local state = map(function(x) return {x, 1} end, sets)

  -- prepare last index to be increased on the first iteration
  state[#state][2] = 0

  local curr = #state -- first thing to increment is the last set

  return function()
    if inc(state, curr) then
      return map(function(s) return s[1][s[2]] end, state)
    else
      return nil
    end
  end
end
_M.permutations = permutations


local function any(pred, t)
  local r
  for _, v in ipairs(t) do
    r = pred(v)
    if r then
      return r
    end
  end
  return false
end


local function member(elem, t)
  return any(function(x) return x == elem end, t)
end


local function is_wildcard(host)
  return find(host, "*") and true
end


local function is_wildcard_route(route)
  return any(is_wildcard, route.hosts)
end


local function is_blank(t)
  return not t or not t[1]
end

function _M.create_default(dao)
  dao = dao or singletons.dao
  local res, err = dao.workspaces:insert({
      name = _M.DEFAULT_WORKSPACE,
  }, { quiet = true })

  if not err then
    dao.workspace_entities:truncate()

    dao.workspace_entities:insert({
        workspace_id = res.id,
        entity_id = res.id,
        entity_type = "workspaces",
        unique_field_name = "name",
        unique_field_value = "default",
  }, { quiet = true })
  end
end


-- Call can come from init phase, Admin or proxy
-- mostly ngx.ctx.workspaces would already be set if not
-- search will be done without workspace
function _M.get_workspaces()
  local r = getfenv(0).__ngx_req
  if not r then
    return {}
  end
  return ngx.ctx.workspaces or {}
end


-- register a relation name and its primary key name as a workspaceable
-- relation
function _M.register_workspaceable_relation(relation, primary_keys, unique_keys)
  -- we explicitly take only the first component of the primary key - ie,
  -- in plugins, this means we only take the plugin ID

  local pks = {}
  for _, pk in ipairs(primary_keys) do
    pks[pk] = true
  end

  if not workspaceable_relations[relation] then
    workspaceable_relations[relation] = {
      primary_key = primary_keys[1],
      primary_keys = pks,
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
        up = function(factory, _, dao)
          local default, err = dao.workspaces:insert({
            name = default_workspace,
          })
          if err then
            return err
          end

          for relation, constraints in pairs(workspaceable_relations) do
            if dao[relation] then
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
            -- todo add migrations for routes and services
          end
        end,
      },
    }
  }
end


-- Coming from admin API request
function _M.get_req_workspace(params)
  local ws_name = params.workspace_name or default_workspace

  local filter
  if ws_name ~= "*" then
    filter = { name = ws_name }
  end

  return singletons.dao.workspaces:run_with_ws_scope({},
    singletons.dao.workspaces.find_all, filter)
end


function _M.add_entity_relation(table_name, entity, workspace)
  local constraints = workspaceable_relations[table_name]

  if constraints and constraints.unique_keys and next(constraints.unique_keys) then
    for k, _ in pairs(constraints.unique_keys) do
      if entity[k] then
        local _, err = add_entity_relation_db(singletons.dao.workspace_entities, workspace.id,
          entity[constraints.primary_key],
          table_name, k, entity[k])
        if err then
          return err
        end
      end
    end
    return
  end

  local _, err = add_entity_relation_db(singletons.dao.workspace_entities, workspace.id,
                                        entity[constraints.primary_key],
                                        table_name, constraints.primary_key,
                                        entity[constraints.primary_key])

  return err
end


function _M.delete_entity_relation(table_name, entity)
  local dao = singletons.dao
  local constraints = workspaceable_relations[table_name]
  if not constraints then
    return
  end

  local res, err = dao.workspace_entities:find_all({
    entity_id = entity[constraints.primary_key],
  })
  if err then
    return err
  end

  for _, row in ipairs(res) do
    local _, err = dao.workspace_entities:delete(row)
    if err then
      return err
    end
    if dao[table_name] then
      local cache_key = dao[table_name]:entity_cache_key(entity)
      if cache and cache_key then
        cache:invalidate(cache_key .. row.workspace_id)
      end
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
        if entity[k] then
          local _, err =  singletons.dao.workspace_entities:update({
            unique_field_value = entity[k]
          }, row)
          if err then
            return err
          end
        end
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


local function match_route(router, method, uri, host)
  return router.select(method, uri, host)
end
_M.match_route = match_route


-- Return sequence of workspace ids an api belongs to
local function api_workspace_ids(api)
  local old_wss = ngx.ctx.workspaces
  ngx.ctx.workspaces = nil
  local ws_rels = singletons.dao.workspace_entities:find_all({entity_id = api.id})
  ngx.ctx.workspaces = old_wss
  return map(function(x) return x.workspace_id end, ws_rels)
end

-- return true if api is in workspace ws
local function is_api_in_ws(api, ws)
  local ws_ids =
    api.workspaces and map(function(ws) return ws.id end, api.workspaces)
      or api_workspace_ids(api)

  return member(ws.id, ws_ids)
end
_M.is_api_in_ws = is_api_in_ws


-- return true if an api with method,uri,host can be added in the
-- workspace ws in the current router. See
-- Workspaces-Design-Implementation quip doc for further detail.
--
-- This function works for both routes/services and APIS, the
-- difference between both being we 'fold' api and route attributes of
-- the selected `route (in the code used as a generic word)`
local function validate_route_for_ws(router, method, uri, host, ws)
  local selected_route = match_route(router, method, uri, host)

  -- XXX: Treating routes and apis the same way. See function comment
  if selected_route and selected_route.route then
    selected_route.api = selected_route.route
  end

  ngx_log(DEBUG, "selected route is " .. tostring(selected_route))
  if selected_route == nil then -- no match ,no conflict
    ngx_log(DEBUG, "no selected_route")
    return true

  elseif is_api_in_ws(selected_route.api, ws) then -- same workspace
    ngx_log(DEBUG, "selected_route in the same ws")
    return true

  elseif is_blank(selected_route.api.hosts) then -- we match from a no-host route
    ngx_log(DEBUG, "selected_route has no host restriction")
    return true

  elseif is_wildcard_route(selected_route.api) then -- has host & it's wildcard

    -- we try to add a wildcard
    if host and is_wildcard(host) and member(host, selected_route.api.hosts) then
      -- ours is also wildcard
      return false
    else
      return true
    end

  elseif host ~= nil then       -- 2.c.ii.1.b
    ngx_log(DEBUG, "host is not nil we collide with other")
    return false

  else -- different ws, selected_route has host and candidate not
    ngx_log(DEBUG, "different ws, selected_route has host and candidate not")
    return true
  end

end
_M.validate_route_for_ws = validate_route_for_ws


local function extract_req_data(params)
  return params.methods, params.uris, params.hosts
end


local function sanitize_ngx_nulls(methods, uris, hosts)
  return (methods == ngx.null) and "" or methods,
         (uris    == ngx.null) and "" or uris,
         (hosts   == ngx.null) and "" or hosts
end


-- workarounds for
-- https://github.com/stevedonovan/Penlight/blob/master/tests/test-stringx.lua#L141-L145
local function split(str)
  local separator = ""
  if str and str ~= "" then
    separator = ","
  end

  return utils.split(str or " ", separator)
end


-- Extracts parameters for an api to be validated against the global
-- current router. An api can have 0..* of each hosts, uris, methods.
-- We check if a route collides with the current setup by trying to
-- match each one of the combinations of accepted [hosts, uris,
-- methods]. The function returns false iff none of the variants
-- collide.
function _M.is_api_colliding(req, router)
  router = router or singletons.api_router
  local methods, uris, hosts = sanitize_ngx_nulls(extract_req_data(req.params))
  local ws = _M.get_workspaces()[1]
  for perm in permutations(split(methods or ALL_METHODS),
                           split(uris),
                           split(hosts)) do
    if not validate_route_for_ws(router, perm[1], perm[2], perm[3], ws) then
      ngx_log(DEBUG, "api collided")
      return true
    end
  end
  return false
end

local function sanitize_route_param(param)
  if (param == cjson.null) or (param == ngx.null) or
    not param or "table" ~= type(param) or
    not next(param) then
    return {[""] = ""}
  else
    return param
  end
end


local function sanitize_routes_ngx_nulls(methods, uris, hosts)
  return sanitize_route_param(methods),
         sanitize_route_param(uris),
         sanitize_route_param(hosts)
end


-- Extracts parameters for a route to be validated against the global
-- current router. An api can have 0..* of each hosts, uris, methods.
-- We check if a route collides with the current setup by trying to
-- match each one of the combinations of accepted [hosts, uris,
-- methods]. The function returns false iff none of the variants
-- collide.
function _M.is_route_colliding(req, router)
  router = router or singletons.router
  local params = req.params
  local methods, uris, hosts = sanitize_routes_ngx_nulls(params.methods, params.paths, params.hosts)

  local ws = _M.get_workspaces()[1]
  for perm in permutations(methods and values(methods) or split(ALL_METHODS),
                           uris and values(uris) or {"/"},
                           hosts and values(hosts) or {""}) do
    if not validate_route_for_ws(router, perm[1], perm[2], perm[3], ws) then
      ngx_log(DEBUG, "route collided")
      return true
    end
  end
  return false
end


local function load_workspace_scope(route)
  local old_wss = ngx.ctx.workspaces
  ngx.ctx.workspaces = {}
  local rows, err = singletons.dao.workspace_entities:find_all({
    entity_id  = route.id,
  })

  ngx.ctx.workspaces = old_wss
  if not rows then
    return nil, err
  end

  return map_unique(function(x) return { id = x.workspace_id } end, rows)
end


-- Return workspace scope, given api belongs
-- to, to the the context.
function _M.resolve_ws_scope(route)
  local ws_scope_key = format("apis_ws_resolution:%s", route.id)
  local workspaces, err = singletons.cache:get(ws_scope_key, nil,
                                               load_workspace_scope, route)
  if err then
    return nil, err
  end
  return workspaces
end


-- given an entity ID, look up its entity collection name;
-- it is only called if the user does not pass in an entity_type
function _M.resolve_entity_type(entity_id)
  local rows, err  = singletons.dao.workspace_entities:find_all({
      entity_id = entity_id
  })
  if err then
    return nil, nil, err
  end
  if not rows[1] then
    return false, nil, "entity " .. entity_id .. " does not belong to any relation"
  end

  local entity_type = rows[1].entity_type

  if singletons.dao[entity_type] then
    rows, err = singletons.dao[entity_type]:find_all({
      [workspaceable_relations[entity_type].primary_key] = entity_id,
      __skip_rbac = true,
    })
    if err then
      return nil, nil, err
    end

    return entity_type, rows[1]
  end

  local row, err = singletons.db[entity_type]:select({
    [workspaceable_relations[entity_type].primary_key] = entity_id,
  }, {skip_rbac = true})
  if err then
    return nil, nil, err
  end

  if not row then
    return false, nil, "entity " .. entity_id .. " not found"
  end

  return entity_type, row
end


function _M.workspace_entities_map(ws_scope, entity_type)
  local ws_entities_map = {}

  for _, ws in ipairs(ws_scope) do
    local ws_entities, err = singletons.dao.workspace_entities:find_all({
      workspace_id = ws.id,
      entity_type = entity_type
    })
    if err then
      return nil, err
    end

    for _, row in ipairs(ws_entities) do
      row.workspace_id = ws.id
      ws_entities_map[row.entity_id] = row
    end
  end

  return ws_entities_map
end


return _M
