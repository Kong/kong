local _M = {}

local bit        = require "bit"
local workspaces = require "kong.workspaces"
local utils      = require "kong.tools.utils"
local cjson      = require "cjson"
local tablex     = require "pl.tablex"
local bcrypt     = require "bcrypt"
local new_tab    = require "table.new"

local band   = bit.band
local bor    = bit.bor
local fmt    = string.format
local lshift = bit.lshift
local rshift = bit.rshift
local find   = string.find
local setmetatable = setmetatable
local getmetatable = getmetatable

local LOG_ROUNDS = 9


local function log(lvl, ...)
  ngx.log(lvl, "[rbac] ", ...)
end


local whitelisted_endpoints = {
  ["/auth"] = true,
  ["/userinfo"] = true,
  ["/admins/register"] = true,
  ["/admins/password_resets"] = true,
  ["/admins/self/password"] = true,
  ["/admins/self/token"] = true,
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
  local relationship_ids, err


  -- workspace_entities doesn't have a "formal" foreign key relationship
  -- with workspace even though the field name is workspace_id so the
  -- search is different for rbac and workspace_entities.
  if factory_key == "workspace_entities" then
    relationship_ids, err = workspaces.compat_find_all(factory_key, {
      [entity_name .. "_id"] = entity_id
    }, { skip_rbac = true })
  else
    relationship_ids, err = workspaces.compat_find_all(factory_key, {
      [entity_name] = { id = entity_id }
    }, { skip_rbac = true })
  end
  if err then
    log(ngx.ERR, "err retrieving relationship via id ", entity_id, ": ", err)
    return nil, err
  end

  return relationship_ids
end


-- fetch the foreign object associated with a mapping id pair
local function retrieve_relationship_entity(foreign_factory_key, foreign_id)
  local relationship, err = kong.db[foreign_factory_key]:select({
    id = foreign_id },
    { skip_rbac = true })
  if err then
    log(ngx.ERR, "err retrieving relationship via id ", foreign_id, ": ", err)
    return nil, err
  end

  return relationship
end


-- fetch the foreign entities associated with a given entity
-- practically, this is used to return the role objects associated with a
-- user, or the permission object associated with a role
-- the kong.cache mechanism is used to cache both the id mapping pairs, as
-- well as the foreign entities themselves
local function entity_relationships(dao_factory, entity, entity_name, foreign, factory_key)
  local cache = kong.cache

  -- get the relationship identities for this identity
  factory_key = factory_key or fmt("rbac_%s_%ss", entity_name, foreign)
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
      relationship_ids[i][foreign].id)

    local relationship, err = cache:get(foreign_factory_cache_key, nil,
                                        retrieve_relationship_entity,
                                        foreign_factory_key,
                                        relationship_ids[i][foreign].id)
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


local function retrieve_user(id)
  local user, err = kong.db.rbac_users:select({id = id}, {
    skip_rbac = true,
  })

  if err then
    log(ngx.ERR, "error in retrieving user", err)
    return nil, err
  end

  if not user then
    log(ngx.DEBUG, "rbac_user not found")
    return nil, nil
  end

  if user.enabled then
    return user
  end
end


local function get_user(id)
  local cache_key = kong.db.rbac_users:cache_key(id)
  local user, err = kong.cache:get(cache_key, nil, retrieve_user, id)
  if err then
    return nil, err
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


local function get_role_entities(db, role, opts)
  opts = opts or {}
  opts.skip_rbac = true
  local res = {}
  for role, err in db.rbac_role_entities:each_for_role({id = role.id}, nil,  opts) do
    if err then
      return nil, err
    end

    table.insert(res, role)
  end

  return res
end
_M.get_role_entities = get_role_entities

local function get_role_endpoints(db, role, opts)
  opts = opts or {}
  opts.skip_rbac = true
  local res = {}
  for role, err in db.rbac_role_endpoints:each_for_role({id = role.id}, nil, opts) do
    if err then
      return nil, err
    end

    table.insert(res, role)
  end

  return res
end
_M.get_role_endpoints = get_role_endpoints


local function get_user_roles(db, user)
  return entity_relationships(db, user, "user", "role", "rbac_user_roles")
end
_M.get_user_roles = get_user_roles


local function get_role_users(db, role)
  return entity_relationships(db, role, "role", "user", "rbac_user_roles")
end
_M.get_role_users = get_role_users


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
    local role_entities, err = _M.get_role_entities(kong.db, role)
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


local function get_rbac_user_info(rbac_user)
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
  local user, err = _M.load_rbac_ctx(kong.db, ctx, rbac_user)

  ctx.workspaces = old_ws_ctx

  if err then
    return nil, err
  end

  return user or guest_user
end
_M.get_rbac_user_info = get_rbac_user_info


local function objects_from_names(db, given_names, object_name)
  local names      = utils.split(given_names, ",")
  local objs       = new_tab(#names, 0)
  local object_dao = fmt("rbac_%ss", object_name)

  for i = 1, #names do
    local object, err = db[object_dao]:select_by_name(names[i])
    if err then
      return nil, err
    end

    if not object then
      return nil, fmt("%s not found with name '%s'", object_name, names[i])
    end

    -- track the whole object so we have the id for the mapping later
    objs[i] = object
  end

  return objs
end
_M.objects_from_names = objects_from_names


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
  role, err = kong.db.rbac_roles:select_by_name(user.name)

  if err then
    return nil, err
  end

  -- if it doesn't exist, create it
  if not role then
    role, err = kong.db.rbac_roles:insert({
      name = user.name,
      comment = "Default user role generated for " .. user.name,
      is_default = true,
    })
    if not role then
      return nil, err
    end
  end

  -- create the user-role association
  local res, err = kong.db.rbac_user_roles:insert({
    user = user,
    role = role ,
  })
  if not res then
    return nil, err
  end

  return user
end


-- helpers: remove entity and endpoint relation when
-- a role is removed
local function role_relation_cleanup(role)
  local db = kong.db
  -- delete the role <-> entity mappings
  local entities, err = get_role_entities(db, role)
  if err then
    return err
  end

  for _, entity in ipairs(entities) do
    local _, err = db.rbac_role_entities:delete(entity)
    if err then
      return err
    end
  end

  -- delete the role <-> endpoint mappings
  local endpoints, err = get_role_endpoints(db, role)
  if err then
    return err
  end

  for _, endpoint in ipairs(endpoints) do
    local _, err = db.rbac_role_endpoints:delete({
      role = { id = endpoint.role_id },
      workspace = endpoint.workspace,
      endpoint = endpoint.endpoint,
    })
    if err then
      return err
    end
  end
end
_M.role_relation_cleanup = role_relation_cleanup


-- helpers: delete the role no rbac_user has that role This is ment to
-- be used on default roles after deleting its main user. Previously
-- this function had to delete the rbac_user_role relationship. Now
-- it's managed by delete-cascade at dao level
function _M.remove_default_role_if_empty(default_role)
  -- get count of users still in the default role
  local users, err = get_role_users(kong.db, default_role)
  local n_users = #users
  if err then
    return nil, err
  end

  -- if count of users in role reached 0, delete it
  if n_users == 0 then
    local _, err = kong.db.rbac_roles:delete({
      id = default_role.id,
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

  local schema = kong.db.daos[table_name].schema
  local entity_id = schema.primary_key[1]

  local function insert()
    return kong.db.rbac_role_entities:insert({
      role = default_role,
      entity_id = entity[entity_id],
      entity_type = table_name,
      actions = bitfield_all_actions,
      negative = false,
    })
  end

  return workspaces.run_with_ws_scope({}, insert)
end
_M.add_default_role_entity_permission = add_default_role_entity_permission


-- remove role-entity permission: remove an entity from the role
-- should be called when entity is deleted or role is removed
local function delete_role_entity_permission(table_name, entity)
  local dao = kong.dao
  local db = kong.db

  local schema = db[table_name] and db[table_name].schema
  if not schema then -- old dao
    schema = dao[table_name].schema
  end

  local entity_id = schema.primary_key[1]
  if schema.fields[entity_id].type == "foreign" then
    entity_id = entity_id .. "_id"
  end

  local role_entities, err, err_t = db.rbac_role_entities:select_all({
    entity_id = entity[entity_id],
    entity_type = table_name
  })
  if err then
    return err_t
  end

  for _, role_entity in ipairs(role_entities) do
    local _, err, err_t = db.rbac_role_entities:delete({
      role = { id = role_entity.role.id },
      entity_id = role_entity.entity_id
    })
    if err then
      return err_t
    end
  end

end
_M.delete_role_entity_permission = delete_role_entity_permission


function _M.narrow_readable_entities(table_name, entities)
  if is_system_table(table_name) or not is_admin_api_request() then -- don't touch it!
    return entities
  end

  local filtered_rows = {}
  setmetatable(filtered_rows, getmetatable(entities))

  for _, entity in ipairs(entities) do
    local valid = _M.validate_entity_operation(entity, table_name)
    if valid then
      filtered_rows[#filtered_rows+1] = entity
    end
  end

  return filtered_rows
end


function _M.validate_entity_operation(entity, table_name)
  -- rbac only applies to the admin api - ie, proxy side
  -- requests are not to be considered
  if not is_admin_api_request() then
    return true
  end

  -- rbac does not apply to "system tables" - e.g., many-to-many tables
  -- like workspace_entities
  if is_system_table(table_name) then
    return true
  end

  -- whitelisted endpoints are also exempt
  if whitelisted_endpoints[ngx.var.uri] then
    return true
  end

  if not kong.configuration or
         kong.configuration.rbac ~= "entity" and
         kong.configuration.rbac ~= "both" then
    return true
  end

  local rbac_ctx, err = get_rbac_user_info()
  if err then
    ngx.log(ngx.ERR, "[rbac] ", err)
    return kong.response.exit(500, { message = "An unexpected error occurred" })
  end

  if rbac_ctx.user == "guest" then
    return false
  end

  local permissions_map = rbac_ctx.entities_perms
  local action = rbac_ctx.action

  local schema = kong.db.daos[table_name].schema

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
    local roles_endpoints, err = get_role_endpoints(kong.db, role)
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

  -- drop workspace prefix from path
  local is_ws_attached = string.find(route_name, "^workspace_")
  if is_ws_attached then
    route_name = ngx.re.gsub(route_name, "^workspace_", "")
    endpoint = ngx.re.gsub(endpoint, "^/" .. workspace, "")
  end

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


-- return the first 5 ascii characters of the hex representation
-- of the token's sha1
local function get_token_ident(rbac_token)
  local str = require "resty.string"

  return string.sub(str.to_hex(ngx.sha1_bin(rbac_token)), 1, 5)
end
_M.get_token_ident = get_token_ident


local function update_user_token(user)
  ngx.log(ngx.DEBUG, "updating user token hash for credential ",
                     user.id)

  local ident  = get_token_ident(user.user_token)
  local digest = bcrypt.digest(user.user_token, LOG_ROUNDS)

  local _, err = kong.db.rbac_users:update(
    { id = user.id }, { user_token = digest, user_token_ident = ident }
  )
  if err then
    ngx.log(ngx.ERR, "error attempting to update user token hash: ", err)
  end
end


-- retrieve a list of all rbac_users from database matching a given ident
-- this function is run outside of workspace scope to simplify ident
-- search logic in conjunction with the need to search in multiple
-- workspaces as introduced in
-- https://github.com/Kong/kong-ee/commit/53dc9dbdce11f01e1cd155161306572bf21fc9d9
--
-- this function is wrapped in an mlcache callback when validating rbac tokens
-- it is called directly by the rbac_user DAO to validate uniqueness of tokens
-- or when searching directly for legacy plaintext tokens
local function retrieve_token_users(ident, k)
  local token_users, err = kong.db.rbac_users:select_all({
    [k] = ident, enabled = true },
    { skip_rbac = true })
  if err then
    return nil, err
  end

  return token_users
end
_M.retrieve_token_users = retrieve_token_users


-- fetch from mlcache a list of rbac_user rows that may be associated with
-- the request's rbac token, by virtue of the token ident
local function get_token_users(rbac_token)
  local ident = get_token_ident(rbac_token)

  local cache_key = "rbac_user_token_ident:" .. ident

  local function cache_get()
    return kong.cache:get(cache_key,
                          nil,
                          retrieve_token_users,
                          ident,
                          "user_token_ident")
  end

  local token_users, err = workspaces.run_with_ws_scope({}, cache_get)
  if err then
    return nil, err
  end

  return token_users
end


-- for a list of rbac_users (possible user given the ident),
-- validate the rbac token digest
local function validate_rbac_token(token_users, rbac_token)
  for _, user in ipairs(token_users) do
    -- fast search to try bcrypt first
    if find(user.user_token, "$2b$", nil, true) then
      if bcrypt.verify(rbac_token, user.user_token) then
        return user
      end

    else
      if user.user_token == rbac_token then
        return user, true -- denote we need to update this value
      end
    end
  end
end
_M.validate_rbac_token = validate_rbac_token


function _M.load_rbac_ctx(dao_factory, ctx, rbac_user)
  local user = rbac_user

  if not user then
    local rbac_auth_header = kong.configuration.rbac_auth_header
    local rbac_token = ngx.req.get_headers()[rbac_auth_header]

    if type(rbac_token) ~= "string" then
      -- forbid empty rbac_token and also
      -- forbid sending rbac_token headers multiple times
      -- because get_user assume it's a string
      return false
    end

    -- token_users is an array of rbac_user objects that may be associated
    -- with the presented token, by virtue of the token's ident
    local token_users, err = get_token_users(rbac_token)
    if err then
      return nil, err
    end

    -- no users found, either the ident isn't found because the token doesn't
    -- exist or because it hasn't yet been updated. fallback to pt search
    if not token_users or #token_users == 0 then
      token_users = retrieve_token_users(rbac_token, "user_token")
    end

    local must_update
    user, must_update = validate_rbac_token(token_users, rbac_token)
    if must_update then
      local old_ws = ngx.ctx.workspaces
      ngx.ctx.workspaces = {}
      update_user_token(user)
      ngx.ctx.workspaces = old_ws
    end

    if not user then
      -- caller assumes this signature means no error and no valid user found
      return nil, nil
    end
  end

  local user_ws_scope, err = workspaces.resolve_user_ws_scope(ctx, user.name)
  if err then
    return kong.response.exit(500, { message = "An unexpected error occurred" })
  end

  if not user_ws_scope or #user_ws_scope == 0 then
    return kong.response.exit(401, {message = "Invalid RBAC credentials"})
  end

  ngx.ctx.workspaces = user_ws_scope
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

  local action, err = figure_action(ngx.req.get_method())
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

function _M.validate_user(rbac_user)
  if kong.configuration.rbac == "off" then
    return
  end

  -- if it's whitelisted, we don't care who the user is
  if whitelisted_endpoints[ngx.var.uri] then
    return true
  end

  local rbac_ctx, err = get_rbac_user_info(rbac_user)
  if err then
    ngx.log(ngx.ERR, "[rbac] ", err)
    return kong.response.exit(500, { message = "An unexpected error occurred" })
  end

  if rbac_ctx.user == "guest" then
    return kong.response.exit(401, { message = "Invalid RBAC credentials" })
  end
end


function _M.validate_endpoint(route_name, route, rbac_user)
  if route_name == "default_route" then
    return
  end

  if not kong.configuration or
         kong.configuration.rbac ~= "both" and
         kong.configuration.rbac ~= "on" then
    return
  end

  local rbac_ctx, err = get_rbac_user_info(rbac_user)
  if err then
    ngx.log(ngx.ERR, "[rbac] ", err)
    return kong.response.exit(500, { message = "An unexpected error occurred" })
  end

  local  ok = _M.authorize_request_endpoint(rbac_ctx.endpoints_perms,
                                            workspaces.get_workspaces()[1].name,
                                            route, route_name, rbac_ctx.action)
  if not ok then
    local err = fmt("%s, you do not have permissions to %s this resource",
                    rbac_ctx.user.name, readable_action(rbac_ctx.action))
    return kong.response.exit(403, { message = err })
  end
end


-- checks whether the given action can be cleanly performed in a
-- set of entities
function _M.check_cascade(entities, rbac_ctx)
  if not kong.configuration or
         kong.configuration.rbac ~= "entity" and
         kong.configuration.rbac ~= "both" then
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

do
  local reports = require "kong.reports"
  local rbac_users_count = function()
    -- XXX consider iterating for :each() workspace, select ws ,
    -- "rbac_users" for performance reasons
    local counts, err = kong.db.workspace_entity_counters:select_all({
      entity_type = "rbac_users"
    })
    if err then
      log(ngx.WARN, "failed to get count of RBAC users: ", err)
      return nil
    end

    local c = 0
    for _, entity_counter in ipairs(counts) do
      c = c + entity_counter.count or 0
    end

    return c
  end

  reports.add_ping_value("rbac_users", rbac_users_count)
end


return _M
