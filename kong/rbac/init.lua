local _M = {}

local bit        = require "bit"
local workspaces = require "kong.workspaces"
local utils      = require "kong.tools.utils"
local cjson      = require "cjson"
local tablex     = require "pl.tablex"
local bcrypt     = require "bcrypt"
local new_tab    = require "table.new"
local base       = require "resty.core.base"

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


-- fetch the foreign object associated with a mapping id pair
local function retrieve_relationship_entity(foreign_factory_key, foreign_id)
  local relationship, err = kong.db[foreign_factory_key]:select({
    id = foreign_id },
    { skip_rbac = true })
  if err then
    return nil, err
  end

  return relationship
end


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


local function retrieve_entity_ids(ws_id)
  local workspaced_entities, err = kong.db.workspace_entities:select_all({
      workspace_id = ws_id
    }, { skip_rbac = true })

  if err then
    log(ngx.ERR, "err retrieving related entities for workspace ", ws_id, ": ", err)
    return nil, err
  end

  return workspaced_entities
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


  local function resolve(workspace_id)
    local workspace_entities, err =
    retrieve_entity_ids(workspace_id)
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


local function retrieve_group(dao, name)
  local entity, err = dao:select_by_name(name)

  if err then
    return nil, err
  end

  return entity
end


local function retrieve_roles_ids(db, user_id)
  local relationship_ids = {}
  for row, err in db.rbac_user_roles:each_for_user({id = user_id }, nil, {skip_rbac = true}) do
    if err then
      return nil, err
    end
    relationship_ids[#relationship_ids + 1] = row
  end

  return relationship_ids
end


local function retrieve_group_roles_ids(db, group_id)
  local relations = {}
  for row, err in db.group_rbac_roles:each_for_group({id = group_id }, nil,
                                                     {skip_rbac = true})
  do
    if err then
      return nil, err
    end
    relations[#relations + 1] = row
  end

  return relations
end


local function select_from_cache(dao, id, retrieve_entity)
  local cache_key = dao:cache_key(id)
  local entity, err = kong.cache:get(cache_key, nil, retrieve_entity, dao, id)

  if err then
    return nil, err
  end

  return entity
end


local function get_user_roles(db, user)
  local cache = kong.cache

  local relationship_cache_key = db.rbac_user_roles:cache_key(user.id)
  local relationship_ids, err = cache:get(relationship_cache_key, nil,
                                          retrieve_roles_ids,
                                          db,
                                          user.id)

  if err then
    log(ngx.ERR, "err retrieving roles for user", user.id, ": ", err)
    return nil, err
  end

  -- now get the relationship objects for each relationship id
  local relationship_objs = {}

  for i = 1, #relationship_ids do
    local foreign_id = relationship_ids[i]["role"].id
    local role_entity_key = db.rbac_roles:cache_key(foreign_id)

    local relationship, err = cache:get(role_entity_key, nil,
      retrieve_relationship_entity, "rbac_roles",foreign_id)
    if err then
      kong.log.err("err retrieving relationship via id ", foreign_id, ": ", err)
      return nil, err
    end

    relationship_objs[#relationship_objs + 1] = relationship
  end

  return relationship_objs
end
_M.get_user_roles = get_user_roles


function _M.get_groups_roles(db, groups)
  if not groups then
    return nil
  end

  local cache = kong.cache

  for k, group_name in ipairs(groups) do
    local group, err = select_from_cache(db.groups, group_name, retrieve_group)
    if err then
      kong.log.err("err retrieving group by name: ", group_name, err)
      return nil, err
    end

    if group then

      local relationship_cache_key = db.group_rbac_roles:cache_key(group.id)
      local relationship_ids, err = cache:get(relationship_cache_key, nil,
                                              retrieve_group_roles_ids, db,
                                              group.id)

      if err then
        kong.log.err("err retrieving group_rbac_roles for group: ", group.id,
                     ": ", err)
        return nil, err
      end

      -- now get the relationship objects for each relationship id
      local relationship_objs = {}

      for i = 1, #relationship_ids do
        local rbac_role_id = relationship_ids[i]["rbac_role"].id
        local role_entity_key = db.rbac_roles:cache_key(rbac_role_id)

        local relationship, err = cache:get(role_entity_key, nil,
          retrieve_relationship_entity, "rbac_roles", rbac_role_id)
        if err then
          kong.log.err("err retrieving rbac_role for id: ", rbac_role_id, ": ", err)
          return nil, err
        end

        relationship_objs[#relationship_objs + 1] = relationship
      end

      return relationship_objs
    end
  end
end


-- allows setting several roles simultaneously, minimizing database accesses
-- @returns true if the new roles were set successfully
-- @returns nil, errors_str, errors_array if there was 1 or more errors
local function set_user_roles(db, user, new_role_names)
  local existing_roles, err = get_user_roles(db, user)
  if err then
    return nil, err, { err }
  end

  local user_pk = { id = user.id }
  local errors = {}

  -- Insert new roles if they are not already inserted
  local existing_hash = {}
  for i = 1, #existing_roles do
    if not existing_roles[i].is_default then
      existing_hash[existing_roles[i].name] = true
    end
  end
  for i = 1, #new_role_names do
    local new_role_name = new_role_names[i]

    if not existing_hash[new_role_name] then
      local role = db.rbac_roles:select_by_name(new_role_name)
      if role then
        local ok, err = db.rbac_user_roles:insert({
          user = user_pk ,
          role = { id = role.id },
        })
        if not ok then
          errors[#errors + 1] = "Error while inserting role: " .. err .. "."
        end
      else
        errors[#errors + 1] = "The given role could not be found by name: " ..
                              new_role_name
      end
    end
  end

  -- Delete existing roles if they are not in the new list of roles
  local new_hash = {}
  for i = 1, #new_role_names do
    new_hash[new_role_names[i]] = true
  end
  for i = 1, #existing_roles do
    if not existing_roles[i].is_default then
      local existing_role_name = existing_roles[i].name
      if not new_hash[existing_role_name] then
        local ok, err = db.rbac_user_roles:delete({
          user = user_pk ,
          role = { id = existing_roles[i].id },
        })
        if not ok then
          errors[#errors + 1] = "Error while deleting role: " .. err .. "."
        end
      end
    end
  end

  local cache_key = db.rbac_user_roles:cache_key(user.id)
  kong.cache:invalidate(cache_key)

  if #errors > 0 then
    return nil, table.concat(errors, ", "), errors
  end

  return true
end
_M.set_user_roles = set_user_roles


local function retrieve_users_ids(db, role_id)
  local relationship_ids = {}
  for row, err in db.rbac_user_roles:each_for_role({id = role_id }, nil, {skip_rbac = true}) do
    if err then
      log(ngx.ERR, "err retrieving users for role", role_id, ": ", err)
      return nil, err
    end
    relationship_ids[#relationship_ids + 1] = row
  end

  return relationship_ids
end


local function get_role_users(db, role)
  local cache = kong.cache

  local relationship_cache_key = db.rbac_user_roles:cache_key(role.id)
  local relationship_ids, err = cache:get(relationship_cache_key, nil,
                                          retrieve_users_ids,
                                          db,
                                          role.id)

  if err then
    log(ngx.ERR, "err retrieving users ids for role: ", err)
    return nil, err
  end

  -- now get the relationship objects for each relationship id
  local relationship_objs = {}

  for i = 1, #relationship_ids do
    local role_entity_key = db.rbac_roles:cache_key(
      relationship_ids[i]["user"].id)

    local relationship, err = cache:get(role_entity_key, nil,
      retrieve_relationship_entity,
      "rbac_users",
      relationship_ids[i]["user"].id)
    if err then
      log(ngx.ERR, "err in retrieving relationship: ", err)
      return nil, err
    end

    relationship_objs[#relationship_objs + 1] = relationship
  end

  return relationship_objs
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


local function get_rbac_user_info(rbac_user, groups)
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
  local user, err = _M.load_rbac_ctx(kong.db, ctx, rbac_user, groups)

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
  local r = base.get_request()
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


-- Merges two rbac_user_roles together by `id` to form the union between roles1
-- and roles2
--@tparam table roles1
--@tparam table roles2
--@tparam table - roles1 ∪ roles2
function _M.merge_roles(roles1, roles2)
  local _roles1 = utils.table_merge({}, roles1)

  if not roles2 then
    return roles1
  end

  local found = {}
  for _, r2 in ipairs(roles2) do
    for _, r1 in ipairs(_roles1) do
      if r1.id == r2.id then
        found[r2.id] = true
        break
      end
    end
    if not found[r2.id] then
      _roles1[#_roles1 + 1] = r2
    end
  end

  return _roles1
end


function _M.load_rbac_ctx(dao_factory, ctx, rbac_user, groups)
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

  local _roles = {}
  local _entities_perms = {}
  local _endpoints_perms = {}
  local group_roles, err = _M.get_groups_roles(dao_factory, groups)
  if err then
    kong.log.err("error getting groups roles", err)
    return kong.response.exit(500, { message = "An unexpected error occurred" })
  end

  for _, workspace in ipairs(user_ws_scope) do
    ngx.ctx.workspaces = { workspace }

    local roles, err = get_user_roles(dao_factory, user)
    if err then
      kong.log.err("error getting user roles", err)
      return kong.response.exit(500, { message = "An unexpected error occurred" })
    end

    print(require("pl.pretty").write({roles, group_roles}))
    roles = _M.merge_roles(roles, group_roles)

    print(require("pl.pretty").write({roles, group_roles}))

    if err then
      return nil, err
    end
    for _, role in pairs(roles) do
      _roles[#_roles + 1] = role
    end

    local entities_perms, _, err = resolve_role_entity_permissions(_roles)
    if err then
      return nil, err
    end

    for id, perm in pairs(entities_perms) do
      _entities_perms[id] = perm
    end

    local endpoints_perms, _, err = resolve_role_endpoint_permissions(_roles)
    if err then
      return nil, err
    end

    for id, perm in pairs(endpoints_perms) do
      _endpoints_perms[id] = perm
    end
  end

  local default_role
  -- retrieve default role
  for _, role in ipairs(_roles) do
    if role.name == user.name then
      default_role = role
      break
    end
  end

  local action, err = figure_action(ngx.req.get_method())
  if err then
    return nil, err
  end

  local rbac_ctx = {
    user = user,
    roles = _roles,
    default_role = default_role,
    action = action,
    entities_perms = _entities_perms,
    endpoints_perms = _endpoints_perms,
  }
  ngx.ctx.rbac = rbac_ctx

  return rbac_ctx
end

function _M.validate_user(rbac_user, groups)
  if kong.configuration.rbac == "off" then
    return
  end

  -- if it's whitelisted, we don't care who the user is
  if whitelisted_endpoints[ngx.var.uri] then
    return true
  end

  local rbac_ctx, err = get_rbac_user_info(rbac_user, groups)
  if err then
    ngx.log(ngx.ERR, "[rbac] ", err)
    return kong.response.exit(500, { message = "An unexpected error occurred" })
  end

  if rbac_ctx.user == "guest" then
    return kong.response.exit(401, { message = "Invalid RBAC credentials" })
  end
end


function _M.validate_endpoint(route_name, route, rbac_user, groups)
  if route_name == "default_route" then
    return
  end

  if not kong.configuration or
         kong.configuration.rbac ~= "both" and
         kong.configuration.rbac ~= "on" then
    return
  end

  local rbac_ctx, err = get_rbac_user_info(rbac_user, groups)
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
