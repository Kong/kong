local _M = {}

local singletons = require "kong.singletons"
local bit        = require "bit"
local workspaces = require "kong.workspaces"
local responses  = require "kong.tools.responses"
local cjson      = require "cjson"
local tablex     = require "pl.tablex"

local band   = bit.band
local bor    = bit.bor
local fmt    = string.format
local lshift = bit.lshift
local rshift = bit.rshift
local setmetatable = setmetatable
local getmetatable = getmetatable


local function log(lvl, ...)
  ngx.log(lvl, "[rbac] ", ...)
end


local whitelisted_endpoints = {
  ["/userinfo"] = true,
}


local actions_bitfields = {
  read   = 0x01,
  create = 0x02,
  update = 0x04,
  delete = 0x08,
}
_M.actions_bitfields = actions_bitfields
local actions_bitfield_size = 4


local bitfield_action = {
  [0x01] = "read",
  [0x02] = "create",
  [0x04] = "update",
  [0x08] = "delete",
}


local bitfield_all_actions = 0x0
for k in pairs(actions_bitfields) do
  bitfield_all_actions = bor(bitfield_all_actions, actions_bitfields[k])
end
_M.bitfield_all_actions = bitfield_all_actions


local figure_action
local readable_action
do
  local action_lookup = setmetatable(
    {
      GET    = actions_bitfields.read,
      HEAD   = actions_bitfields.read,
      POST   = actions_bitfields.create,
      PATCH  = actions_bitfields.update,
      PUT    = actions_bitfields.update,
      DELETE = actions_bitfields.delete,
    },
    {
      __index = function(t, k)
        error("Invalid method")
      end,
      __newindex = function(t, k, v)
        error("Cannot write to method lookup table")
      end,
    }
  )

  figure_action = function(method)
    return action_lookup[method]
  end

  readable_action = function(action)
    return bitfield_action[action]
  end

  _M.figure_action = figure_action
  _M.readable_action = readable_action
end


-- fetch the id pair mapping of related objects from the database
local function retrieve_relationship_ids(entity_id, entity_name, factory_key)
  local relationship_ids, err = singletons.dao[factory_key]:find_all({
    [entity_name .. "_id"] = entity_id,
    __skip_rbac = true,
  })
  if err then
    log(ngx.ERR, "err retrieving relationship via id ", entity_id, ": ", err)
    return nil, err
  end

  return relationship_ids
end


-- fetch the foreign object associated with a mapping id pair
local function retrieve_relationship_entity(foreign_factory_key, foreign_id)
  local relationship, err = singletons.dao[foreign_factory_key]:find_all({
    id = foreign_id,
    __skip_rbac = true,
  })
  if err then
    log(ngx.ERR, "err retrieving relationship via id ", foreign_id, ": ", err)
    return nil, err
  end

  return relationship[1]
end


-- fetch the foreign entities associated with a given entity
-- practically, this is used to return the role objects associated with a
-- user, or the permission object associated with a role
-- the kong.cache mechanism is used to cache both the id mapping pairs, as
-- well as the foreign entities themselves
local function entity_relationships(dao_factory, entity, entity_name, foreign)
  local cache = singletons.cache

  -- get the relationship identities for this identity
  local factory_key = fmt("rbac_%s_%ss", entity_name, foreign)
  local relationship_cache_key = dao_factory[factory_key]:cache_key(entity.id)
  local relationship_ids, err = cache:get(relationship_cache_key, nil,
                                          retrieve_relationship_ids,
                                          entity.id, entity_name, factory_key)
  if err then
    log(ngx.ERR, "err retrieving relationship ids for ", entity_name, ": ", err)
    return nil, err
  end

  -- now get the relationship objects for each relationship id
  local relationship_objs = {}
  local foreign_factory_key = fmt("rbac_%ss", foreign)

  for i = 1, #relationship_ids do
    local foreign_factory_cache_key = dao_factory[foreign_factory_key]:cache_key(
      relationship_ids[i][foreign .. "_id"])

    local relationship, err = cache:get(foreign_factory_cache_key, nil,
                                        retrieve_relationship_entity,
                                        foreign_factory_key,
                                        relationship_ids[i][foreign .. "_id"])
    if err then
      log(ngx.ERR, "err in retrieving relationship: ", err)
      return nil, err
    end

    relationship_objs[#relationship_objs + 1] = relationship
  end

  return relationship_objs
end
_M.entity_relationships = entity_relationships


-- predicate answering if a user (rbac_ctx) is able to manage
-- endpoints from workspace (workspace). Answer is true if user has
-- all permissions over all endpoints of that workspace ("*" being a
-- general case of it)
local function user_can_manage_endpoints_from(rbac_ctx, workspace)
  return
    (rbac_ctx.endpoints_perms[workspace]
      and rbac_ctx.endpoints_perms[workspace]["*"] == bitfield_all_actions)
    or
    (rbac_ctx.endpoints_perms["*"]
      and rbac_ctx.endpoints_perms["*"]["*"] == bitfield_all_actions)
end
_M.user_can_manage_endpoints_from = user_can_manage_endpoints_from


local function retrieve_user(user_token_or_name, key)
  local users, err = singletons.dao.rbac_users:find_all({
    [key] = user_token_or_name,
    __skip_rbac = true,
  })
  if err then
    log(ngx.ERR, "error in retrieving user from token: ", err)
    return nil, err
  end

  for _, user in ipairs(users) do
    if user.enabled then
      return user
    end
  end
end


local function get_user(user_token_or_name, key)
  key = key or "user_token"

  if key ~= "name" and key ~= "user_token" then
    return nil, "key must be 'name' or 'user_token'"
  end

  local user, err

  -- we're only caching by user token
  if key == "user_token" then
    local cache_key = singletons.dao.rbac_users:cache_key(user_token_or_name)
    user, err = singletons.cache:get(cache_key, nil,
                                     retrieve_user, user_token_or_name, key)

    if err then
      return nil, err
    end

  else
    -- look up user in db
    local users, err = singletons.dao.rbac_users:run_with_ws_scope(
                       {},
                       singletons.dao.rbac_users.find_all,
                       { [key] = user_token_or_name })

    if err then
      return nil, err
    end

    user = users[1]
  end

  return user
end
_M.get_user = get_user


local function bitfield_check(map, key, bit)
  local keys = {
    key, -- exact match has priority
    "*", -- wildcard
  }

  for _, key in ipairs(keys) do
    -- first, verify negative permissions
    if map[key] and band(rshift(map[key], 4), bit) == bit then
      return false
    end

    -- then, positive permissions
    if map[key] and band(map[key], bit) == bit then
      return true
    end
  end

  return false
end


local function arr_hash_add(t, e)
  if not t[e] then
    t[e] = true
    t[#t + 1] = e
  end
end


-- given a list of workspace IDs, return a list/hash
-- of entities belonging to the workspaces, handling
-- circular references
function _M.resolve_workspace_entities(workspaces)
  -- entities = {
  --    [1] = "foo",
  --    foo = 1,
  --
  --    [2] = "bar",
  --    bar = 2
  -- }
  local entities = {}


  local seen_workspaces = {}


  local function resolve(workspace)
    local workspace_entities, err =
      retrieve_relationship_ids(workspace, "workspace", "workspace_entities")
    if err then
      error(err)
    end

    local iter_entities = {}

    for _, ws_entity in ipairs(workspace_entities) do
      local ws_id  = ws_entity.workspace_id
      local e_id   = ws_entity.entity_id
      local e_type = ws_entity.entity_type

      if e_id == ws_id then -- luacheck: ignore
        -- As the default workspace has this row where entity_id ==
        -- workspace_id, we would start recursing over itself. We
        -- don't want to recurse on it), and we dont' want to add it
        -- to the list of object relations either
      elseif e_type == "workspaces" then
        assert(seen_workspaces[ws_id] == nil, "already seen workspace " ..
                                              ws_id)
        seen_workspaces[ws_id] = true

        local recursed_entities = resolve(e_id)

        for _, e in ipairs(recursed_entities) do
          arr_hash_add(iter_entities, e)
        end

      else
        arr_hash_add(iter_entities, e_id)
      end
    end

    return iter_entities
  end


  for _, workspace in ipairs(workspaces) do
    local es = resolve(workspace)
    for _, e in ipairs(es) do
      arr_hash_add(entities, e)
    end
  end


  return entities
end


local function resolve_role_entity_permissions(roles)
  local pmap = {}
  local nmap = {} -- map endpoints to a boolean indicating whether it is
                  -- negative or not

  local function positive_mask(p, id)
    pmap[id] = bor(p, pmap[id] or 0x0)
    nmap[id] = false
  end
  local function negative_mask(p, id)
    pmap[id] = bor(pmap[id] or 0x0, lshift(p, 4))
    nmap[id] = true
  end

  local function iter(role_entities, mask)
    for _, role_entity in ipairs(role_entities) do
      if role_entity.entity_type == "workspaces" then
        -- list/hash
        local es = _M.resolve_workspace_entities({ role_entity.entity_id })

        for _, child_id in ipairs(es) do
          mask(role_entity.actions, child_id)
        end
      else
        mask(role_entity.actions, role_entity.entity_id)
      end
    end
  end

  -- assign all the positive bits first such that we dont have a case
  -- of an explicit positive overriding an explicit negative based on
  -- the order of iteration
  local positive_entities, negative_entities =  {}, {}
  for _, role in ipairs(roles) do
    local role_entities, err = singletons.dao.rbac_role_entities:find_all({
      role_id  = role.id,
      __skip_rbac = true,
    })
    if err then
      return _, _, err
    end

    for _, role_entity in ipairs(role_entities) do
      if role_entity.negative then
        negative_entities[#negative_entities + 1] = role_entity
      else
        positive_entities[#positive_entities + 1] = role_entity
      end
    end
  end

  iter(positive_entities, positive_mask)
  iter(negative_entities, negative_mask)

  return pmap, nmap
end
_M.resolve_role_entity_permissions = resolve_role_entity_permissions


local function get_rbac_user_info()
  local guest_user = {
    roles = {},
    user = "guest",
    entities_perms = {},
    endpoints_perms = {},
  }

  local ok, res = pcall(function() return ngx.ctx.rbac end)
  local user = ok and res
  if user then
    return user
  end

  local ctx = ngx.ctx
  local old_ws_ctx = ctx.workspaces
  local user, err =  _M.load_rbac_ctx(singletons.dao, ctx)
  if err then
    ctx.workspaces = old_ws_ctx
    return nil, err
  end
  ctx.workspaces = old_ws_ctx
  return user or guest_user
end
_M.get_rbac_user_info = get_rbac_user_info


local function is_system_table(t)
  local reserved_tables = { "workspace*" }
  for _, v in ipairs(reserved_tables) do
    if string.find(t, v) then
      return true
    end
  end

  return false
end
_M.is_system_table = is_system_table

local function is_admin_api_request()
  local r = getfenv(0).__ngx_req
  if not r then
    return false
  end

  return ngx.ctx.admin_api_request
end


-- helper: create default role and the corresponding user-role association
-- user: the rbac user entity
function _M.create_default_role(user)
  local role, err

  -- try fetching the role; if it exists, use it
  role, err = singletons.dao.rbac_roles:find_all({
    name = user.name,
  })
  if err then
    return nil, err
  end
  role = role[1]

  -- if it doesn't exist, create it
  if not role then
    role, err = singletons.dao.rbac_roles:insert({
      name = user.name,
      comment = "Default user role generated for " .. user.name,
      is_default = true,
    })
    if not role then
      return nil, err
    end
  end

  -- create the user-role association
  local res, err = singletons.dao.rbac_user_roles:insert({
    user_id = user.id,
    role_id = role.id,
  })
  if not res then
    return nil, err
  end

  return true
end


-- helpers: remove entity and endpoint relation when
-- a role is removed
local function role_relation_cleanup(role)
  local dao = singletons.dao
  -- delete the role <-> entity mappings
  local entities, err = dao.rbac_role_entities:find_all({
    role_id = role.id,
  })
  if err then
    return err
  end

  for _, entity in ipairs(entities) do
    local _, err = dao.rbac_role_entities:delete(entity)
    if err then
      return err
    end
  end

  -- delete the role <-> endpoint mappings
  local endpoints, err = dao.rbac_role_endpoints:find_all({
    role_id = role.id,
  })
  if err then
    return err
  end

  for _, endpoint in ipairs(endpoints) do
    local _, err = dao.rbac_role_endpoints:delete(endpoint)
    if err then
      return err
    end
  end
end
_M.role_relation_cleanup = role_relation_cleanup


-- helpers: remove user from default role; delete the role if the
-- user was the only one in the role
function _M.remove_user_from_default_role(user, default_role)
  -- delete user-role relationship
  local _, err = singletons.dao.rbac_user_roles:delete({
    user_id = user.id,
    role_id = default_role.id,
  })
  if err then
    return nil, err
  end

  -- get count of users still in the default role
  local n_users, err = singletons.dao.rbac_user_roles:count({
    role_id = default_role.id,
  })
  if err then
    return nil, err
  end

  -- if count of users in role reached 0, delete it
  if n_users == 0 then
    local err = role_relation_cleanup(default_role)
    if err then
      return nil, err
    end

    local _, err = singletons.dao.rbac_roles:delete({
      id = default_role.id,
      name = default_role.name,
    })
    if err then
      return nil, err
    end
  end

  return true
end


-- add default role-entity permission: adds an entity to the
-- current user's default role; as the owner of the entity,
-- the user is allowed to perform any action
local function add_default_role_entity_permission(entity, table_name)
  if is_system_table(table_name) or not is_admin_api_request()
    or not ngx.ctx.rbac then
    return true
  end

  local default_role = ngx.ctx.rbac.default_role
  if not default_role then
    return true
  end

  local schema
  if singletons.dao[table_name] then -- old dao
    schema = singletons.dao[table_name].schema

  else -- new dao
    schema = singletons.db.daos[table_name].schema
  end

  local entity_id = schema.primary_key[1]

  return singletons.dao.rbac_role_entities:insert({
    role_id = default_role.id,
    entity_id = entity[entity_id],
    entity_type = table_name,
    actions = bitfield_all_actions,
    negative = false,
  })
end
_M.add_default_role_entity_permission = add_default_role_entity_permission


-- remove role-entity permission: remove an entity from the role
-- should be called when entity is deleted or role is removed
local function delete_role_entity_permission(table_name, entity)
  local schema
  local dao = singletons.dao
  if dao[table_name] then -- old dao
    schema = dao[table_name].schema

  else -- new dao
    schema = singletons.db.daos[table_name].schema
  end

  local entity_id = schema.primary_key[1]

  local res, err = dao.rbac_role_entities:find_all({
    entity_id = entity[entity_id],
    entity_type = table_name,
  })
  if err then
    return err
  end

  for _, row in ipairs(res) do
    local _, err = dao.rbac_role_entities:delete(row)
    if err then
      return err
    end
  end
end
_M.delete_role_entity_permission = delete_role_entity_permission


function _M.narrow_readable_entities(db_table_name, entities)
  local filtered_rows = {}
  setmetatable(filtered_rows, getmetatable(entities))
  if not is_system_table(db_table_name) and is_admin_api_request() then
    for i, v in ipairs(entities) do
      local valid = _M.validate_entity_operation(v, db_table_name)
      if valid then
        filtered_rows[#filtered_rows+1] = v
      end
    end

    return filtered_rows
  else
    return entities
  end
end


function _M.validate_entity_operation(entity, table_name)
  -- rbac only applies to the admin api - ie, proxy side
  -- requests are not to be considered
  if not is_admin_api_request() then
    return true
  end

  -- whitelisted endpoints are also exempt
  if whitelisted_endpoints[ngx.var.request_uri] then
    return true
  end

  if not singletons.configuration or
         singletons.configuration.rbac ~= "entity" and
         singletons.configuration.rbac ~= "both" then
    return true
  end

  local rbac_ctx = get_rbac_user_info()
  if rbac_ctx.user == "guest" then
    return false
  end

  local permissions_map = rbac_ctx.entities_perms
  local action = rbac_ctx.action

  local schema
  if singletons.dao[table_name] then -- old dao
    schema = singletons.dao[table_name].schema

  else -- new dao
    schema = singletons.db.daos[table_name].schema
  end

  local entity_id = schema.primary_key[1]

  return _M.authorize_request_entity(permissions_map, entity[entity_id], action)
end


function _M.readable_entities_permissions(roles)
  local map, nmap = resolve_role_entity_permissions(roles)

  for k, v in pairs(map) do
    local actions_t = setmetatable({}, cjson.empty_array_mt)
    local actions_t_idx = 0

    for action, n in pairs(actions_bitfields) do
      if band(n, v) == n then
        actions_t_idx = actions_t_idx + 1
        actions_t[actions_t_idx] = action
      end
    end

    map[k] = {
      actions = actions_t,
      negative = nmap[k]
    }
  end

  return map
end


local function authorize_request_entity(map, id, action)
  return bitfield_check(map, id, action)
end
_M.authorize_request_entity = authorize_request_entity


local function resolve_role_endpoint_permissions(roles)
  local pmap = {}
  local nmap = {} -- map endpoints to a boolean indicating whether it is
                  -- negative or not

  for _, role in ipairs(roles) do
    local roles_endpoints, err = singletons.dao.rbac_role_endpoints:find_all({
      role_id = role.id,
      __skip_rbac = true,
    })
    if err then
      return _, _, err
    end

    -- because we hold a two-dimensional mapping and prioritize explicit
    -- mapping matches over endpoint globs, we need to hold both the negative
    -- and positive bit sets independantly, instead of having a negative bit
    -- unset a positive bit, because in doing so it would be impossible to
    -- determine implicit vs. explicit authorization denial (the former leading
    -- to a fall-through in the 2-d array, the latter leading to an immediate
    -- denial)
    for _, role_endpoint in ipairs(roles_endpoints) do
      if not pmap[role_endpoint.workspace] then
        pmap[role_endpoint.workspace] = {}
      end

      -- store explicit negative bits adjacent to the positive bits in the mask
      local p = role_endpoint.actions
      if role_endpoint.negative then
        p = bor(p, lshift(p, 4))
      end

      local ws_prefix = ""
      if role_endpoint.endpoint ~= "*" then
        ws_prefix = "/" .. role_endpoint.workspace
      end

      -- is it negative or positive?
      nmap[ws_prefix .. role_endpoint.endpoint] = role_endpoint.negative

      pmap[role_endpoint.workspace][ws_prefix .. role_endpoint.endpoint] =
        bor(p, pmap[role_endpoint.workspace][role_endpoint.endpoint] or 0x0)
    end
  end


  return pmap, nmap
end
_M.resolve_role_endpoint_permissions = resolve_role_endpoint_permissions


function _M.readable_endpoints_permissions(roles)
  local map, nmap = resolve_role_endpoint_permissions(roles)

  for workspace in pairs(map) do
    for endpoint, actions in pairs(map[workspace]) do
      local actions_t = setmetatable({}, cjson.empty_array_mt)
      local actions_t_idx = 0

      for action, n in pairs(actions_bitfields) do
        if band(n, actions) == n then
          actions_t_idx = actions_t_idx + 1
          actions_t[actions_t_idx] = action
        end
      end

      map[workspace][endpoint] = {
        actions = actions_t,
        negative = nmap[endpoint],
      }
    end
  end

  return map
end


-- normalized route_name: replace lapis named parameters with *, so that
-- any named parameters match wildcard endpoints
local function normalize_route_name(route_name)
  route_name = ngx.re.gsub(route_name, "^workspace_", "")
  route_name = ngx.re.gsub(route_name, ":[^/]*", "*")
  route_name = ngx.re.gsub(route_name, "/$", "")
  return route_name
end

-- return a list of paths from route_name, replacing the most
-- rightmost section of the path which not a wildcard already by the
-- wildcard "*" until all sections are wildcards
--
-- example: generalize_with_wildcards("/foo/bar/baz") ->
-- {"/foo/bar/*", "/foo/*/*", "/*/*/*" }
local function generalize_with_wildcards(route_name)
  route_name = ngx.re.gsub(route_name, "^workspace_", "")
  route_name = ngx.re.gsub(route_name, "/$", "")
  local n
  local res = {}

  res[1], n = ngx.re.sub(string.reverse(route_name), "^[^*/]+", "*")
  while n == 1 do
    res[#res+1] ,n = ngx.re.sub(res[#res], "/[^*/]+", "/*")
  end
  res[#res] = nil

  return tablex.imap(string.reverse, res)
end
_M.generalize_with_wildcards = generalize_with_wildcards

-- return a list of endpoints; if the incoming request endpoint
-- matches either one of them, we get a positive or negative match
local function get_endpoints(workspace, endpoint, route_name)
  local endpoint_with_workspace = "/" .. workspace .. endpoint
  local normalized_route_name = normalize_route_name(route_name)
  local normalized_route_name_with_workspace = "/" .. workspace .. normalized_route_name
  local wildcarded_endpoints = generalize_with_wildcards(endpoint)
  local wildcarded_endpoints_with_ws = generalize_with_wildcards(endpoint_with_workspace)

  -- order is important:
  --  - first, try to match exact endpoint name
  --    * without workspace name prepended - e.g., /apis/test
  --    * with workspace name prepended - e.g., /foo/apis/test
  --  - normalized route name
  --    * without workspace name prepended - e.g., /apis/*
  --    * with workspace name prepended - e.g., /foo/apis/*
  --  - sequence of endpoints with path segments substituted by * progressively
  --  - sequence of endpoints+workspace with path segments substituted by * progressively
  local endpoints = {
    endpoint,
    endpoint_with_workspace,
    normalized_route_name,
    normalized_route_name_with_workspace,
  }

  for _, v in ipairs(wildcarded_endpoints) do
    table.insert(endpoints, v)
  end
  for _, v in ipairs(wildcarded_endpoints_with_ws) do
    table.insert(endpoints, v)
  end

  table.insert(endpoints,"*")

  return endpoints
end


function _M.authorize_request_endpoint(map, workspace, endpoint, route_name, action)
  if whitelisted_endpoints[endpoint] then
    return true
  end

  -- look for
  -- 1. explicit allow (and _no_ explicit) deny in the specific ws/endpoint
  -- 2. "" in the ws/*
  -- 3. "" in the */endpoint
  -- 4. "" in the */*
  --
  -- explit allow means a match on the lower bit set
  -- and no match on the upper bits. if theres no match on the lower set,
  -- no need to check the upper bit set
  for _, workspace in ipairs{workspace, "*"} do
    if map[workspace] then
      for _, endpoint in ipairs(get_endpoints(workspace, endpoint, route_name)) do
        local perm = map[workspace][endpoint]
        if perm then
          if band(perm, action) == action then
            if band(rshift(perm, actions_bitfield_size), action) == action then
              return false
            else
              return true
            end
          end
        end
      end
    end
  end

  return false
end


function _M.load_rbac_ctx(dao_factory, ctx)
  local rbac_auth_header = singletons.configuration.rbac_auth_header
  local rbac_token = ngx.req.get_headers()[rbac_auth_header]
  local http_method = ngx.req.get_method()
  if type(rbac_token) ~= "string" then
    -- forbid empty rbac_token and also
    -- forbid sending rbac_token headers multiple times
    -- because get_user assume it's a string
    return false
  end
  local user, err = get_user(rbac_token)
  if err then
    return nil, err
  end
  if not user then
    local user_ws_scope, err = workspaces.resolve_user_ws_scope(ctx, rbac_token)
    if err then
      return responses.send_HTTP_INTERNAL_SERVER_ERROR()
    end

    if not user_ws_scope or #user_ws_scope == 0 then
      return responses.send_HTTP_UNAUTHORIZED("Invalid RBAC credentials")
    end

    ctx.workspaces = user_ws_scope
    user, err = get_user(rbac_token)
    if err or not user then
      return nil, err
    end
  end

  local roles, err = entity_relationships(dao_factory, user, "user", "role")
  if err then
    return nil, err
  end

  local default_role
  -- retrieve default role
  for _, role in ipairs(roles) do
    if role.name == user.name then
      default_role = role
      break
    end
  end

  local action, err = figure_action(http_method)
  if err then
    return nil, err
  end

  local entities_perms, _, err = resolve_role_entity_permissions(roles)
  if err then
    return nil, err
  end

  local endpoints_perms, _, err = resolve_role_endpoint_permissions(roles)
  if err then
    return nil, err
  end

  local rbac_ctx = {
    user = user,
    roles = roles,
    default_role = default_role,
    action = action,
    entities_perms = entities_perms,
    endpoints_perms = endpoints_perms,
  }
  ngx.ctx.rbac = rbac_ctx

  return rbac_ctx
end

function _M.validate_user()
  if singletons.configuration.rbac == "off" then
    return
  end

  -- if it's whitelisted, we don't care who the user is
  if whitelisted_endpoints[ngx.var.request_uri] then
    return true
  end

  local rbac_ctx, err = get_rbac_user_info()
  if err then
    ngx.log(ngx.ERR, "[rbac] ", err)
    return responses.send_HTTP_INTERNAL_SERVER_ERROR()
  end

  if rbac_ctx.user == "guest" then
    return responses.send_HTTP_UNAUTHORIZED("Invalid RBAC credentials")
  end
end


function _M.validate_endpoint(route_name, route)
  if route_name == "default_route" then
    return
  end

  if not singletons.configuration or
         singletons.configuration.rbac ~= "both" and
         singletons.configuration.rbac ~= "on" then
    return
  end

  local rbac_ctx, err = get_rbac_user_info()
  if err then
    ngx.log(ngx.ERR, "[rbac] ", err)
    return responses.send_HTTP_INTERNAL_SERVER_ERROR()
  end

  local  ok = _M.authorize_request_endpoint(rbac_ctx.endpoints_perms,
                                            workspaces.get_workspaces()[1].name,
                                            route, route_name, rbac_ctx.action)
  if not ok then
    local err = fmt("%s, you do not have permissions to %s this resource",
                    rbac_ctx.user.name, readable_action(rbac_ctx.action))
    return responses.send_HTTP_FORBIDDEN(err)
  end
end


-- checks whether the given action can be cleanly performed in a
-- set of entities
function _M.check_cascade(entities, rbac_ctx)
  if not singletons.configuration or
         singletons.configuration.rbac ~= "entity" and
         singletons.configuration.rbac ~= "both" then
    return true
  end

  --
  -- entities = {
  --  [table name] = {
  --    entities = {
  --      ...
  --    },
  --    schema = {
  --      ...
  --    }
  --  }
  -- }
  for _, table_info in pairs(entities) do
    for _, entity in ipairs(table_info.entities) do
      if not authorize_request_entity(rbac_ctx.entities_perms,
                                      entity[table_info.schema.primary_key[1]],
                                      rbac_ctx.action) then
        return false
      end
    end
  end

  return true
end


local function retrieve_consumer_user_map(rbac_user_id)
  local users, err = singletons.dao.consumers_rbac_users_map:find_all({
    user_id = rbac_user_id,
    __skip_rbac = true,
  })

  if err then
    log(ngx.ERR, "error retrieving consumer_user map from rbac_user.id: ",
        rbac_user_id, err)
    return nil, err
  end

  if not next(users) then
    return nil
  end

  return users[1]
end


--- Retrieve rbac <> consumer map
-- @param `rbac_user_id` id of rbac_user
function _M.get_consumer_user_map(rbac_user_id)
  local cache_key = singletons.dao.consumers_rbac_users_map:cache_key(rbac_user_id)
  local user, err = singletons.cache:get(cache_key,
                                         nil,
                                         retrieve_consumer_user_map,
                                         rbac_user_id)

  if err then
    return nil, err
  end

  return user
end


function _M.get_rbac_token()
  local rbac_auth_header = singletons.configuration.rbac_auth_header
  local rbac_token = ngx.req.get_headers()[rbac_auth_header]

  if type(rbac_token) ~= "string" then
    -- forbid empty rbac_token and also
    -- forbid sending rbac_token headers multiple times
    -- because get_user assume it's a string
    return false
  end

  return rbac_token
end


do
  local reports = require "kong.core.reports"
  local rbac_users_count = function()
    local c, err = singletons.dao.rbac_users:count()
    if not c then
      log(ngx.WARN, "failed to get count of RBAC users: ", err)
      return nil
    end

    return c
  end

  reports.add_ping_value("rbac_users", rbac_users_count)
end


return _M
