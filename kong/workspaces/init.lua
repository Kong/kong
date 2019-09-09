local singletons = require "kong.singletons"
local utils = require "kong.tools.utils"
local tablex = require "pl.tablex"
local cjson = require "cjson.safe"
local ws_dao_wrappers = require "kong.workspaces.dao_wrappers"
local counters = require "kong.workspaces.counters"
local base = require "resty.core.base"


local find    = string.find
local format  = string.format
local ngx_log = ngx.log
local DEBUG   = ngx.DEBUG
local next    = next
local values = tablex.values
local pairs = pairs
local setmetatable = setmetatable
local ipairs = ipairs
local type = type
local utils_split = utils.split
local ngx_null = ngx.null
local tostring = tostring
local inc_counter = counters.inc_counter
local table_concat = table.concat
local table_remove = table.remove


local _M = {}

local DEFAULT_WORKSPACE = "default"
local WORKSPACE_DELIMETER = ":"
local ALL_METHODS = "GET,POST,PUT,DELETE,OPTIONS,PATCH"


_M.DEFAULT_WORKSPACE = DEFAULT_WORKSPACE
_M.WORKSPACE_DELIMITER = WORKSPACE_DELIMETER


-- XXX compat_find_all will go away with workspaces remodel
local compat_find_all = ws_dao_wrappers.compat_find_all
_M.compat_find_all = compat_find_all


-- a map of workspaceable relations to its primary key name
local workspaceable_relations = {}


-- used only with insert, update, delete, and find_all
local unique_accross_ws = {
  plugins    = true,
  rbac_users = true,
  workspaces = true,
  workspace_entities = true,
  snis = true,
}
_M.unique_accross_ws = unique_accross_ws


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


function _M.upsert_default(db)
  db = db or singletons.db or kong.db -- XXX EE: safeguard to catch db if available anywhere.

  local cb = function()
    return db.workspaces:upsert_by_name(DEFAULT_WORKSPACE, {
      name = DEFAULT_WORKSPACE
    })
  end

  local res, err = _M.run_with_ws_scope({}, cb)
  if err then
    return nil, err
  end

  db:truncate("workspace_entities")
  ngx.ctx.workspaces = { res }

  return res
end


-- -- Call can come from init phase, Admin or proxy
-- -- mostly ngx.ctx.workspaces would already be set if not
-- -- search will be done without workspace
-- local function get_workspaces()
--   local curr_phase
--   local ok, res = pcall(function()
--     ngx.log(ngx.ERR, [[ngx.ctx.workspaces:]], require("inspect")(ngx.ctx.workspaces))
--     return true
--   end)

--   if not ok then
--     return {}
--   end

--   if ok then
--     return ngx.ctx.workspaces or {}
--   end
-- end

local function get_workspaces()
  local r = base.get_request()

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
  return setmetatable({},  {
    __index = workspaceable_relations,
    __newindex = function()
      error "immutable table"
    end,
    __pairs = function()
      return next, workspaceable_relations, nil
    end,
    __metatable = false,
  })
end
_M.get_workspaceable_relations = get_workspaceable_relations



-- Coming from admin API request
-- Fetch a workspace entity from its name
function _M.fetch_workspace(ws_name)
  -- XXX do we ever need this function to return all workspaces (*)?
  -- if we do, we have a problem (find_all not supported, but we can
  -- iterate over pages)

  return _M.run_with_ws_scope(
    {},
    kong.db.workspaces.select_by_name,
    kong.db.workspaces,
    ws_name
  )
end


do
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


  function _M.add_entity_relation(table_name, entity, workspace)
    local constraints = workspaceable_relations[table_name]

    if constraints and constraints.unique_keys and next(constraints.unique_keys) then
      for k, _ in pairs(constraints.unique_keys) do
        if not constraints.primary_keys[k] and entity[k] then
          local _, err = add_entity_relation_db(kong.db.workspace_entities,
                                                workspace,
                                                entity[constraints.primary_key],
                                                table_name,
                                                k,
                                                entity[k])
          if err then
            return err
          end
        end
      end
    end

    inc_counter(kong.db, workspace.id, table_name, entity, 1);
    local _, err = add_entity_relation_db(kong.db.workspace_entities, workspace,
                                          entity[constraints.primary_key],
                                          table_name, constraints.primary_key,
                                          entity[constraints.primary_key])

    return err
  end
end


function _M.delete_entity_relation(table_name, entity)
  local db = kong.db

  local constraints = workspaceable_relations[table_name]
  if not constraints then
    return
  end

  local res, err = db.workspace_entities:select_all({
    entity_id = entity[constraints.primary_key],
  }, {skip_rbac = true})
  if err then
    return err
  end

  local seen = {}
  for _, row in ipairs(res) do
    local _, err = db.workspace_entities:delete({
      entity_id = row.entity_id,
      workspace_id = row.workspace_id,
      unique_field_name = row.unique_field_name,
    }, {skip_rbac = true})
    if err then
      return err
    end

    if not seen[row.workspace_id] then
      inc_counter(kong.db, row.workspace_id, table_name, entity, -1);
      seen[row.workspace_id] = true
    end
  end

end


function _M.update_entity_relation(table_name, entity)
  local constraints = workspaceable_relations[table_name]
  if constraints and constraints.unique_keys then
    for k, _ in pairs(constraints.unique_keys) do
      local res, err = kong.db.workspace_entities:select_all({
        entity_id = entity[constraints.primary_key],
        unique_field_name = k,
      })
      if err then
        return err
      end

      for _, row in ipairs(res) do
        if entity[k] then
          local pk = {
            entity_id = row.entity_id,
            workspace_id = row.workspace_id,
            unique_field_name = row.unique_field_name,
          }
          local _, err =  kong.db.workspace_entities:update(pk, {
            unique_field_value = entity[k]
          })
          if err then
            return err
          end
        end
      end
    end
  end
end


local function find_entity_by_unique_field(params)
  local rows, err = kong.db.workspace_entities:select_all(params)
  if err then
    return nil, err
  end
  if rows then
    return rows[1]
  end
end
_M.find_entity_by_unique_field = find_entity_by_unique_field

local function find_workspaces_by_entity(params)
  local rows, err = kong.db.workspace_entities:select_all(params)
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
  local ws_rels = kong.db.workspace_entities:select_all({entity_id = entity.id})
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
    if type(perm[1]) ~= "string" or
       type(perm[2]) ~= "string" or
       type(perm[3]) ~= "string" then
         return false -- we can't check for collisions. let the
                      -- schema validator handle the type error
    end

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
  local old_wss = ctx.workspaces
  ctx.workspaces = {}

  local rows, err = kong.db.workspace_entities:select_all({
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
  local rows, err = kong.db.workspace_entities:select_all({
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
  local rows, err = kong.db.workspace_entities:select_all({
      entity_id = entity_id
  })
  if err then
    return nil, nil, err
  end
  if not rows[1] then
    return false, nil, "entity " .. entity_id .. " does not belong to any relation"
  end

  local entity_type = rows[1].entity_type

  local row, err = kong.db[entity_type]:select({
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
  local r = base.get_request()
  if not r then
    return false
  end
  return ngx.ctx.is_proxy_request
end
_M.is_proxy_request = is_proxy_request


local function load_entity_map(ws_scope, table_name)
  local ws_entities_map = {}
  for _, ws in ipairs(ws_scope) do
    local primary_key = workspaceable_relations[table_name].primary_key

    local ws_entities, err = kong.db.workspace_entities:select_all({
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
  local ws_scope = ws_scope or get_workspaces()

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
      field_schema.type ~= "id" and  params[field_name] ~= ngx_null then
      params[field_name] = format("%s%s%s", workspace.name, WORKSPACE_DELIMETER,
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
        return nil, err
      end

      if row then
        -- don't clear primary keys
        if not constraints.primary_keys[k] then
          params[k] = nil
        end
        params[constraints.primary_key] = row.entity_id
        return params
      end
    end
  end
end


function _M.remove_ws_prefix(table_name, row, include_ws)
  if not row then
    return
  end

  local constraints = workspaceable_relations[table_name]
  if not constraints or not constraints.unique_keys then
    return row
  end

  for field_name, field_schema in pairs(constraints.unique_keys) do
    -- skip if no unique key or it's also a primary, field
    -- is not set or has null value
    if row[field_name] and constraints.primary_key ~= field_name and
       field_schema.type ~= "id" and row[field_name] ~= ngx_null and
       type(row[field_name]) == "string" then

      local names = utils_split(row[field_name], WORKSPACE_DELIMETER)
      if #names > 1 then
        table_remove(names, 1)
        row[field_name] = table_concat(names, WORKSPACE_DELIMETER)
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


local function run_with_ws_scope(ws_scope, cb, ...)
  local old_ws = ngx.ctx.workspaces
  ngx.ctx.workspaces = ws_scope
  local res, err = cb(...)
  ngx.ctx.workspaces = old_ws
  return res, err
end
_M.run_with_ws_scope = run_with_ws_scope


-- validates that given primary_key belongs to current ws scope
function _M.validate_pk_exist(table_name, params, constraints, workspace)
  if not constraints or not constraints.primary_key then
    return true
  end

  if table_name == "workspaces" and
    params.name == DEFAULT_WORKSPACE then
    return true
  end

  local workspace = workspace or get_workspaces()[1]
  if not workspace then
    return true
  end

  local row, err = find_entity_by_unique_field({
    workspace_id = workspace.id,
    entity_id = params[constraints.primary_key]
  })

  if err then
    return false, err
  end

  return row and true
end


-- true if the table is workspaceable and the workspace name is not
-- the wildcard - which should evaluate to all workspaces - and we are not
-- retrieving the default workspace itself
--
-- this is to break the cycle: some methods here - e.g., find_all -
-- need to retrieve the current workspace entity, which is set in
-- `before_filter`, but to set the entity some of those same methods are
-- used
function _M.is_workspaceable(table_name, ws_scope)
  return workspaceable_relations[table_name] and #ws_scope > 0
end


local function encode_ws_list(ws_scope)
  local ids = {}
  for _, ws in ipairs(ws_scope) do
    ids[#ids + 1] = "'" .. tostring(ws.id) .. "'"
  end
  return table_concat(ids, ", ")
end


function _M.ws_scope_as_list(table_name)
  local ws_scope = get_workspaces()

  if workspaceable_relations[table_name] and #ws_scope > 0 then
    return encode_ws_list(ws_scope)
  end
end


function _M.get_workspace()
  return ngx.ctx.workspaces and ngx.ctx.workspaces[1] or {}
end


-- used to retrieve workspace specific configuration values.
-- * config must exist in default configuration or will result
--   in an error.
-- * if workspace specific config does not exist fall back to
--   default config value.
-- * if 'opts.explicitly_ws' flag evaluates to true, workspace config
--   will be returned, even if it is nil/null
-- * if 'opts.decode_json' and conf is string, will decode and return table
function _M.retrieve_ws_config(config_name, workspace, opts)
  local conf
  opts = opts or {}

  if opts.explicitly_ws or workspace.config and
    workspace.config[config_name] ~= nil and
    workspace.config[config_name] ~= ngx.null then
    conf = workspace.config[config_name]
  else
    if singletons.configuration then
      conf = singletons.configuration[config_name]
    end
  end

  -- if table, return a copy so that we don't mutate the conf
  if type(conf) == "table" then
    return utils.deep_copy(conf)
  end

  if opts.decode_json and type(conf) == "string" then
    local json_conf, err = cjson.decode(conf)
    if err then
      return nil, err
    end

    return json_conf
  end

  return conf
end


function _M.build_ws_admin_gui_url(config, workspace)
  local admin_gui_url = config.admin_gui_url
  -- this will only occur when smtp_mock is on
  -- otherwise, conf_loader will throw an error if
  -- admin_gui_url is nil
  if not admin_gui_url then
    return ""
  end

  if not workspace.name or workspace.name == "" then
    return admin_gui_url
  end

  return admin_gui_url .. "/" .. workspace.name
end


function _M.build_ws_portal_gui_url(config, workspace)
  if not config.portal_gui_host
    or not config.portal_gui_protocol
    or not workspace.name then
    return config.portal_gui_host
  end

  if config.portal_gui_use_subdomains then
    return config.portal_gui_protocol .. '://' .. workspace.name .. '.' .. config.portal_gui_host
  end

  return config.portal_gui_protocol .. '://' .. config.portal_gui_host .. '/' .. workspace.name
end


function _M.build_ws_portal_api_url(config)
  return config.portal_api_url
end


function _M.build_ws_portal_cors_origins(workspace)
  -- portal_cors_origins takes precedence
  local portal_cors_origins = _M.retrieve_ws_config("portal_cors_origins", workspace)
  if portal_cors_origins and #portal_cors_origins > 0 then
    return portal_cors_origins
  end

  -- otherwise build origin from protocol, host and subdomain, if applicable
  local subdomain = ""
  local portal_gui_use_subdomains = _M.retrieve_ws_config("portal_gui_use_subdomains", workspace)
  if portal_gui_use_subdomains then
    subdomain = workspace.name .. "."
  end

  local portal_gui_protocol = _M.retrieve_ws_config("portal_gui_protocol", workspace)
  local portal_gui_host = _M.retrieve_ws_config("portal_gui_host", workspace)

  return { portal_gui_protocol .. "://" .. subdomain .. portal_gui_host }
end


function _M.split_prefix(name)
  if not name then
    return
  end

  local names = utils_split(name, WORKSPACE_DELIMETER)
  if #names > 1 then
    local prefix = names[1]
    table_remove(names, 1)
    return prefix, table_concat(names, WORKSPACE_DELIMETER)
  end
end


return _M
