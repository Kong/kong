local cassandra = require "cassandra"
local singletons = require "kong.singletons"
local utils      = require "kong.tools.utils"
local tablex = require "pl.tablex"
local cjson = require "cjson"

local enums = require "kong.enterprise_edition.dao.enums"


local find    = string.find
local format  = string.format
local ngx_log = ngx.log
local DEBUG   = ngx.DEBUG
local next    = next
local values = tablex.values
local cache = singletons.cache
local pairs = pairs
local setmetatable = setmetatable
local ipairs = ipairs
local type = type
local getfenv = getfenv
local utils_split = utils.split
local ngx_null = ngx.null
local tostring = tostring
local concat = table.concat


local _M = {}

local default_workspace = "default"
local workspace_delimiter = ":"

_M.DEFAULT_WORKSPACE = default_workspace
_M.WORKSPACE_DELIMITER = workspace_delimiter
local ALL_METHODS = "GET,POST,PUT,DELETE,OPTIONS,PATCH"


-- a map of workspaceable relations to its primary key name
local workspaceable_relations = {}


-- used only with insert, update, delete, and find_all
local unique_accross_ws = {
  plugins    = true,
  rbac_users = true,
  workspaces = true,
  workspace_entities = true,
}


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
  return not t or (type(t) == "table" and not t[1])
end


function _M.create_default(dao)
  dao = dao or singletons.dao

  local res, err = dao.workspaces:run_with_ws_scope({}, dao.workspaces.find_all, {
    name = default_workspace,
  })
  if err then
    return nil, err
  end
  if res and res[1] then
    ngx.ctx.workspaces = {res[1]}
    return res[1]
  end

  -- if it doesn't exist, create it...
  res, err = dao.workspaces:insert({
      name = _M.DEFAULT_WORKSPACE,
  }, { quiet = true })
  if not res then
    return nil, err
  end

  dao.workspace_entities:truncate()
  dao.workspace_entities:insert({
    workspace_id = res.id,
    workspace_name = res.name,
    entity_id = res.id,
    entity_type = "workspaces",
    unique_field_name = "id",
    unique_field_value = res.id,
  }, { quiet = true })

  dao.workspace_entities:insert({
    workspace_id = res.id,
    workspace_name = res.name,
    entity_id = res.id,
    entity_type = "workspaces",
    unique_field_name = "name",
    unique_field_value = res.name,
  }, { quiet = true })

  ngx.ctx.workspaces = {res}

  return res
end


-- Call can come from init phase, Admin or proxy
-- mostly ngx.ctx.workspaces would already be set if not
-- search will be done without workspace
local function get_workspaces()
  local r = getfenv(0).__ngx_req
  if not r then
    return {}
  end
  return ngx.ctx.workspaces or {}
end
_M.get_workspaces = get_workspaces


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


local function get_workspaceable_relations()
  return setmetatable({}, metatable(workspaceable_relations))
end
_M.get_workspaceable_relations = get_workspaceable_relations


local function add_entity_relation_db(dao, ws, entity_id, table_name, field_name, field_value)
  return dao:insert({
    workspace_id = ws.id,
    entity_id = entity_id,
    entity_type = table_name,
    unique_field_name = field_name or "",
    unique_field_value = field_value or "",
    workspace_name = ws.name,
  })
end


-- return migration for adding default workspace and existing
-- workspaceable entities to the default workspace
function _M.get_default_workspace_migration()

  local prefix_separator = format("%s%s", default_workspace, workspace_delimiter)

  local function pg_batch_update_entities_with_ws_prefix(dao, relation, constraints)
    local unique_fields_updates = {}
    local unique_fields_wheres = {}
    local sample_unique_field
    for k, _ in pairs(constraints.unique_keys) do
      if not constraints.primary_keys[k] then
        sample_unique_field = sample_unique_field or k

        table.insert(unique_fields_updates,
                     format(" %s = '%s' || %s ",
                            k,
                            prefix_separator,
                            k))

        table.insert(unique_fields_wheres,
                     format("( %s IS NOT NULL AND %s NOT LIKE '%s%%' )",
                            k, k, prefix_separator))
      end
    end

    if unique_accross_ws[relation] then
      return
    end

    if sample_unique_field then
      local update_query = format("update %s set %s where %s",
                                  relation,
                                  concat(unique_fields_updates, ", "),
                                  concat(unique_fields_wheres, " or "))
      local _, err = dao.db:query(update_query)
      if err then
        return nil, err
      end
    end

    return true
  end


  local function cas_update_entity_with_ws_prefix(dao, relation, entity, constraints, default_ws)
    local err, _
    local updates = {}
    for k, v in pairs(constraints.unique_keys) do
      if not constraints.primary_keys[k] and entity[k] then
        updates[k] = entity[k]
      end
    end

    local old_ws = ngx.ctx.workspaces
    ngx.ctx.workspaces = {default_ws}
    if next(updates) then
      _, err = dao[relation]:update(updates, entity)
    end
    ngx.ctx.workspaces = old_ws
    if err then
      return nil, err
    end

    return true
  end

  local function escape_string(str)
    return string.gsub(str, "'", "''")
  end


  return {
    default_workspace = {
      {
        name = "2018-02-16-110000_default_workspace_entities",
        up = function(factory, _, dao)

          singletons.dao = singletons.dao or dao

          local _, err = dao:truncate_table("workspace_entities")
          if err then
            return err
          end

          _, err = dao:truncate_table("workspaces")
          if err then
            return err
          end

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
                return err
              end

              for _, entity in ipairs(entities) do
                if constraints.unique_keys then
                  for k, _ in pairs(constraints.unique_keys) do
                    if not constraints.primary_keys[k] and entity[k] then
                      local _, err = add_entity_relation_db(dao.workspace_entities, default,
                                                            entity[constraints.primary_key],
                                                            relation, k, entity[k])
                      if err then
                        return err
                      end
                    end
                  end

                end
                local _, err = add_entity_relation_db(dao.workspace_entities, default,
                                                      entity[constraints.primary_key],
                                                      relation, constraints.primary_key,
                                                      entity[constraints.primary_key])
                if err then
                  return err
                end

                if factory.name == "cassandra" and relation ~= "workspaces" then
                  local _, err = cas_update_entity_with_ws_prefix(dao, relation, entity, constraints, default)
                  if err then
                    return err
                  end
                end
              end

              if factory.name == "postgres" and relation ~= "workspaces" then
                local _, err = pg_batch_update_entities_with_ws_prefix(dao, relation, constraints)
                if err then
                  return err
                end
              end
            end
          end

          -- Add new-dao entities (routes and services)
          if factory.name == "postgres" then
            local services =  dao.db:query("select * from services;")
            for _, entity in ipairs(services) do
              local _, err = add_entity_relation_db(dao.workspace_entities,
                                                    default,
                                                    entity.id,
                                                    "services",
                                                    "name",
                                                    entity.name)
              if err then
                return err
              end

              _, err = add_entity_relation_db(dao.workspace_entities,
                                              default,
                                              entity.id,
                                              "services",
                                              "id",
                                              entity.id)
              if err then
                return err
              end
            end

            local _, err = dao.db:query(
              format("update services set name = '%s' || name where name NOT LIKE '%s%%'",
                     prefix_separator,
                     prefix_separator))
            if err then
              return err
            end


            local routes, err = dao.db:query("select * from routes;")
            if err then
              return err
            end

            for _, route in ipairs(routes) do
              local _, err = add_entity_relation_db(dao.workspace_entities,
                                                    default,
                                                    route.id,
                                                    "routes",
                                                    "id",
                                                    route.id)
              if err then
                return err
              end
            end

          else  -- cassandra
            local coordinator  = dao.db:get_coordinator()
            for rows, err, page in coordinator:iterate("SELECT * FROM services",
                                                       nil,
                                                       {page_size = 1000}) do
              if err then
                return err
              end
              for _, service in ipairs(rows) do
                service.name = string.gsub(service.name, "^" .. prefix_separator, "")

                local _, err = add_entity_relation_db(
                  dao.workspace_entities,
                  default,
                  service.id,
                  "services",
                  "name",
                  service.name)
                if err then
                  return err
                end

                _, err = add_entity_relation_db(dao.workspace_entities,
                                                default,
                                                service.id,
                                                "services",
                                                "id",
                                                service.id)
                if err then
                  return err
                end

                local q = format("UPDATE services SET name = '%s' WHERE id = %s and partition = 'services';",
                  format("%s%s", prefix_separator, escape_string(service.name)),
                  service.id,
                  escape_string(service.name))
                _, err = dao.db:query(q)
                if err then
                  return err
                end
              end
            end

            coordinator  = dao.db:get_coordinator()
            for rows, err, page in coordinator:iterate("SELECT * FROM routes",
                                                       nil,
                                                       {page_size = 1000}) do
              if err then
                return err
              end

              for _, route in ipairs(rows) do
                local _, err = add_entity_relation_db(dao.workspace_entities,
                  default, route.id, "routes", "id", route.id)
                if err then
                  return err
                end
              end
            end
          end
        end,
      },
    }
  }
end


-- Coming from admin API request
function _M.get_req_workspace(ws_name)

  local filter
  if ws_name ~= "*" then
    filter = { name = ws_name }
  end

  return singletons.dao.workspaces:run_with_ws_scope({},
    singletons.dao.workspaces.find_all, filter)
end

local inc_counter
function _M.add_entity_relation(table_name, entity, workspace)
  local constraints = workspaceable_relations[table_name]

  if constraints and constraints.unique_keys and next(constraints.unique_keys) then
    for k, _ in pairs(constraints.unique_keys) do
      if not constraints.primary_keys[k] and entity[k] then
        local _, err = add_entity_relation_db(singletons.dao.workspace_entities, workspace,
          entity[constraints.primary_key],
          table_name, k, entity[k])
        if err then
          return err
        end
      end
    end
  end

  inc_counter(singletons.dao, workspace.id, table_name, entity, 1);
  local _, err = add_entity_relation_db(singletons.dao.workspace_entities, workspace,
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
    __skip_rbac = true
  })
  if err then
    return err
  end

  local seen = {}
  for _, row in ipairs(res) do
    local _, err = dao.workspace_entities:delete(row, {__skip_rbac = true})
    if err then
      return err
    end

    if dao[table_name] then
      local cache_key = dao[table_name]:entity_cache_key(entity)
      if cache and cache_key then
        cache:invalidate(cache_key .. row.workspace_id)
      end
    end

    if not seen[row.workspace_id] then
      inc_counter(singletons.dao, row.workspace_id, table_name, entity, -1);
      seen[row.workspace_id] = true
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


local function find_entity_by_unique_field(params)
  local rows, err = singletons.dao.workspace_entities:find_all(params)
  if err then
    return nil, err
  end
  if rows then
    return rows[1]
  end
end
_M.find_entity_by_unique_field = find_entity_by_unique_field

local function find_workspaces_by_entity(params)
  local rows, err = singletons.dao.workspace_entities:find_all(params)
  if err then
    return nil, err
  end
  if next(rows) then
    return rows
  end
end
_M.find_workspaces_by_entity = find_workspaces_by_entity

local function match_route(router, method, uri, host)
  return router.select(method, uri, host)
end
_M.match_route = match_route


-- Return sequence of workspace ids an entity belongs to
local function entity_workspace_ids(entity)
  local old_wss = ngx.ctx.workspaces
  ngx.ctx.workspaces = nil
  local ws_rels = singletons.dao.workspace_entities:find_all({entity_id = entity.id})
  ngx.ctx.workspaces = old_wss
  return map(function(x) return x.workspace_id end, ws_rels)
end


-- return true if route is in workspace ws
local function is_route_in_ws(route, ws)
  local ws_ids =
    route.workspaces and map(function(ws) return ws.id end, route.workspaces)
      or entity_workspace_ids(route)

  return member(ws.id, ws_ids)
end
_M.is_route_in_ws = is_route_in_ws


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
  if selected_route and selected_route.api then
    selected_route.route = selected_route.api
  end

  ngx_log(DEBUG, "selected route is " .. tostring(selected_route))
  if selected_route == nil then -- no match ,no conflict
    ngx_log(DEBUG, "no selected_route")
    return true

  elseif is_route_in_ws(selected_route.route, ws) then -- same workspace
    ngx_log(DEBUG, "selected_route in the same ws")
    return true

  elseif is_blank(selected_route.route.hosts) or
    ngx_null == selected_route.route.hosts then -- we match from a no-host route
    ngx_log(DEBUG, "selected_route has no host restriction")
    return false

  elseif is_wildcard_route(selected_route.route) then -- has host & it's wildcard

    -- we try to add a wildcard
    if host and is_wildcard(host) and member(host, selected_route.route.hosts) then
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
  return (methods == ngx_null) and "" or methods,
         (uris    == ngx_null) and "" or uris,
         (hosts   == ngx_null) and "" or hosts
end


-- workarounds for
-- https://github.com/stevedonovan/Penlight/blob/master/tests/test-stringx.lua#L141-L145
local function split(str_or_tbl)
  if type(str_or_tbl) == "table" then
    return str_or_tbl
  end

  local separator = ""
  if str_or_tbl and str_or_tbl ~= "" then
    separator = ","
  end

  return utils_split(str_or_tbl or " ", separator)
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
  for perm in permutations(split(is_blank(methods) and ALL_METHODS or methods),
                           split(is_blank(uris)    and {"/"} or uris),
                           split(is_blank(hosts)   and {""} or hosts)) do
    if not validate_route_for_ws(router, perm[1], perm[2], perm[3], ws) then
      ngx_log(DEBUG, "api collided")
      return true
    end
  end
  return false
end

local function sanitize_route_param(param)
  if (param == cjson.null) or (param == ngx_null) or
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


local function unique_workspaces(workspace_entities)
  local r = {}
  local seen = {}
  local n = 0
  for _, x in ipairs(workspace_entities) do
    local ws_id = x.workspace_id
    if ws_id and not seen[ws_id] then
      n = n + 1
      r[n] = {id = ws_id, name = x.workspace_name}
      seen[ws_id] = true
    end
  end
  return r
end


-- Return the list of current workspaces given a route. `route` is the
-- matched route from the router. Special handling of portal routes is
-- done matching them by id as portal creates routes on memory that do
-- not have a representation in the db. Therefore they don't exist in
-- workspace_entities. See kong/enterprise_edition/proxies.lua
local function load_workspace_scope(ctx, route)
  if route.id == "00000000-0000-0000-0002-000000000000" or
    route.id == "00000000-0000-0000-0000-000000000004" or
    route.id == "00000000-0000-0000-0004-000000000000" or
    route.id == "00000000-0000-0000-0000-000000000003" or
    route.id == "00000000-0000-0000-0003-000000000000" or
    route.id == "00000000-0000-0000-0006-000000000000"
  then
    return singletons.dao.workspaces:find_all({name = default_workspace})
  end

  local old_wss = ctx.workspaces
  ctx.workspaces = {}
  local rows, err = singletons.dao.workspace_entities:find_all({
    entity_id  = route.id,
    unique_field_name = "id",
    unique_field_value = route.id,
  })
  ctx.workspaces = old_wss

  if err or not rows[1] then
    return nil, err
  end

  return unique_workspaces(rows)
end


-- Return workspace scope, given api belongs
-- to, to the the context.
function _M.resolve_ws_scope(ctx, route)

  local ws_scope_key = format("apis_ws_resolution:%s", route.id)
  local workspaces, err = singletons.cache:get(ws_scope_key, nil,
                                               load_workspace_scope, ctx, route)
  if err then
    return nil, err
  end
  return utils.deep_copy(workspaces)
end


local function load_user_workspace_scope(ctx, name)
  local old_wss = ctx.workspaces
  ctx.workspaces = {}
  local rows, err = singletons.dao.workspace_entities:find_all({
    entity_type  = "rbac_users",
    unique_field_name = "name",
    unique_field_value = name,
  })
  ctx.workspaces = old_wss

  if err or not rows[1] then
    return nil, err
  end

  return unique_workspaces(rows)
end


-- Return workspace scope, given api belongs
-- to, to the the context.
function _M.resolve_user_ws_scope(ctx, name)
  return load_user_workspace_scope(ctx, name)
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


local function is_proxy_request()
  local r = getfenv(0).__ngx_req
  if not r then
    return false
  end
  return ngx.ctx.is_proxy_request
end
_M.is_proxy_request = is_proxy_request


local workspaceable = get_workspaceable_relations()
local function load_entity_map(ws_scope, table_name)
  local ws_entities_map = {}
  for _, ws in ipairs(ws_scope) do
    local primary_key = workspaceable[table_name].primary_key

    local ws_entities, err = singletons.dao.workspace_entities:find_all({
      workspace_id = ws.id,
      entity_type = table_name,
      unique_field_name = primary_key,
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

-- cache entities map in memory for current request
-- ws_scope table has a life of current proxy request only
local entity_map_cache = setmetatable({}, { __mode = "k" })
local function workspace_entities_map(ws_scope, table_name)
  local ws_scope = get_workspaces()

  if not is_proxy_request() then
    return load_entity_map(ws_scope, table_name)
  end

  local ws_entities_cached = entity_map_cache[ws_scope]
  if not ws_entities_cached then
    ws_entities_cached = {}
    entity_map_cache[ws_scope] = ws_entities_cached
  end

  if ws_entities_cached[table_name] then
    return ws_entities_cached[table_name]
  end

  local entity_map = load_entity_map(ws_scope, table_name)
  ws_entities_cached[table_name] = entity_map
  return entity_map
end
_M.workspace_entities_map = workspace_entities_map


function _M.apply_unique_per_ws(table_name, params, constraints)
  -- entity may have workspace_id, workspace_name fields, ex. in case of update
  -- needs to be removed as entity schema doesn't support them
  if table_name ~= "workspace_entities" and table_name ~= "workspace_entity_counters" then
    params.workspace_id = nil
    params.workspace_name = nil
  end

  if not constraints then
    return
  end

  local workspace = get_workspaces()[1]
  if not workspace or unique_accross_ws[table_name] then
    return workspace
  end

  for field_name, field_schema in pairs(constraints.unique_keys) do
    if params[field_name] and not constraints.primary_keys[field_name] and
      field_schema.schema.fields[field_name].type ~= "id" and  params[field_name] ~= ngx_null then
      params[field_name] = format("%s%s%s", workspace.name, workspace_delimiter,
                                  params[field_name])
    end
  end
  return workspace
end


-- If entity has a unique key it will have workspace_name prefix so we
-- have to search first in the relationship table
function _M.resolve_shared_entity_id(table_name, params, constraints)
  if unique_accross_ws[table_name] then
    return
  end

  local ws_scope = get_workspaces()
  if #ws_scope == 0 then
    return
  end

  if not constraints or not constraints.unique_keys then
    return
  end

  for k, v in pairs(params) do
    if constraints.unique_keys[k] then
      local row, err = find_entity_by_unique_field({
        workspace_id = ws_scope[1].id,
        entity_type = table_name,
        unique_field_name = k,
        unique_field_value = v,
      })

      if err then
        return false, err
      end

      if row then
        -- don't clear primary keys
        if not constraints.primary_keys[k] then
          params[k] = nil
        end
        params[constraints.primary_key] = row.entity_id
        return true
      end
    end
  end
end


function _M.remove_ws_prefix(table_name, row, include_ws)
  if not row then
    return
  end

  local constraints = workspaceable[table_name]
  if not constraints or not constraints.unique_keys then
    return
  end

  for field_name, field_schema in pairs(constraints.unique_keys) do
    if row[field_name] and not constraints.primary_keys[field_name] and
      field_schema.schema.fields[field_name].type ~= "id" and  row[field_name] ~= ngx_null then
      local names = utils_split(row[field_name], workspace_delimiter, 2)
      if #names > 1 then
        row[field_name] = names[2]
      end
    end
  end

  if not include_ws then
    if table_name ~= "workspace_entities" then
      row.workspace_id = nil
    end
    row.workspace_name = nil
  end
end


function _M.run_with_ws_scope(ws_scope, cb, ...)
  local old_ws = ngx.ctx.workspaces
  ngx.ctx.workspaces = ws_scope
  local res, err = cb(...)
  ngx.ctx.workspaces = old_ws
  return res, err
end


-- Entity count management

local function counts(workspace_id)
  local counts, err = singletons.dao.workspace_entity_counters:find_all({workspace_id = workspace_id})
  if err then
    return nil, err
  end

  local res = {}
  for _, v in ipairs(counts) do
    res[v.entity_type] = v.count
  end

  return res
end
_M.counts = counts


-- Return if entity is relevant to entity counts per workspace. Only
-- non-proxy consumers should not be counted.
local function should_be_counted(dao, entity_type, entity)
  if entity_type ~= "consumers" then
    return true
  end

  -- some call sites do not provide the consumer.type and only pass
  -- the id of the entity. In that case, we have to first fetch the
  -- complete entity object
  if not entity.type then
    local err
    entity, err = dao[entity_type]:find({id = entity.id})
    if err then
      return nil, err
    end
    if not entity then
      -- The entity is not in the DB. We might be in the middle of the
      -- callback.
      return false
    end
  end

  if entity.type ~= enums.CONSUMERS.TYPE.PROXY then
    return false
  end

  return true
end


inc_counter = function(dao, ws, entity_type, entity, count)

  if not should_be_counted(dao, entity_type, entity) then
    return
  end

  if dao.db_type == "cassandra" then

    local _, err = dao.db.cluster:execute([[
      UPDATE workspace_entity_counters set
      count=count + ? where workspace_id = ? and entity_type= ?]],
      {cassandra.counter(count), cassandra.uuid(ws), entity_type},
      {
        counter = true,
        prepared = true,
    })
    if err then
      return nil, err
    end
  else

    local incr_counter_query = [[
      INSERT INTO workspace_entity_counters(workspace_id, entity_type, count)
      VALUES('%s', '%s', %d)
      ON CONFLICT(workspace_id, entity_type) DO
      UPDATE SET COUNT = workspace_entity_counters.count + excluded.count]]
    local _, err = dao.db:query(format(incr_counter_query, ws, entity_type, count))
    if err then
      return nil, err
    end
  end
end
_M.inc_counter = inc_counter


local function get_counts_for_ws(dao, workspace_id)
  local entity_types = {}
  for relation, constraints in pairs(get_workspaceable_relations()) do
    entity_types[relation] = constraints.primary_key
  end

  local counts = {}
  for k, v in pairs(entity_types) do
    local res, err = dao.workspace_entities:find_all({
      workspace_id = workspace_id,
      entity_type = k,
      unique_field_name = v,
    })
    if err then
      return nil, err
    end

    counts[k] = #res


    -- When the migration that initializes the workspace counts runs, check
    -- if there's only one admin consumer in a given workspace. If so, do not
    -- count it. This has the effect that new installations do not see
    -- consumer count =1.
    -- Only do this check when count is 1 as we accept small divergences for
    -- bigger numbers.
    if k == "consumers" and counts[k] == 1 then
      local consumer, err = dao.consumers:find({id = res[1].unique_field_value})
      if not err and consumer.type ~= enums.CONSUMERS.TYPE.PROXY then
        counts[k] = 0
      end
    end

  end

  return counts
end


local function initialize_counters_migration(dao)
  local workspaces, err = dao.workspaces:find_all()
  if err then
    return nil, err
  end

  local workspaces_counts = {}
  for _, ws in ipairs(workspaces) do
    workspaces_counts[ws.id] = get_counts_for_ws(dao, ws.id)
  end

  for k, v in pairs(workspaces_counts) do
    for entity_type, count in pairs(v) do
      dao.workspace_entity_counters:insert({
        workspace_id = k,
        entity_type = entity_type,
        count = count,
      })
    end
  end
end


local function get_initialize_workspace_entity_counters_migration()
  return
    {
      workspace_counters = {
        {
        name = "2018-10-11-164515_fill_counters",
        up = function(_, _, dao)
          initialize_counters_migration(dao)
        end,
        }
      }
    }
end
_M.get_initialize_workspace_entity_counters_migration = get_initialize_workspace_entity_counters_migration


return _M
