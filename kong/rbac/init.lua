-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local _M = {}

local bit        = require "bit"
local workspaces = require "kong.workspaces"
local utils      = require "kong.tools.utils"
local cjson      = require "cjson"
local tablex     = require "pl.tablex"
local stringx    = require "pl.stringx"
local bcrypt     = require "bcrypt"
local secret     = require "kong.plugins.oauth2.secret"
local digest     = require "resty.openssl.digest"
local new_tab    = require "table.new"
local base       = require "resty.core.base"
local hooks      = require "kong.hooks"
local resty_str  = require "resty.string"
local constants  = require "kong.constants"

local BCRYPT_COST_FACTOR = constants.RBAC.BCRYPT_COST_FACTOR

local band   = bit.band
local bor    = bit.bor
local fmt    = string.format
local lshift = bit.lshift
local rshift = bit.rshift
local find   = string.find
local null   = ngx.null
local setmetatable = setmetatable
local getmetatable = getmetatable
local register_hook = hooks.register_hook
local to_hex = resty_str.to_hex
local ipairs = ipairs
local EMPTY_T = {}


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
_M._bitfield_all_actions = bitfield_all_actions -- for tests only


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
      OPTIONS = actions_bitfields.read,
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

  _M.readable_action = readable_action
end


local _hooks_loaded
function _M.register_dao_hooks(db)
  if _hooks_loaded then
    return
  end
  _hooks_loaded = true

  local function skip_rbac(options)
    return options and options.skip_rbac
  end

  local function page(entities, name, options)
    if skip_rbac(options) then
      return entities
    end

    return _M.narrow_readable_entities(name, entities)
  end

  register_hook("dao:page:post", page)
  register_hook("dao:page_for:post", page)

  register_hook("dao:select_by:post", function(row, name, options)
    if skip_rbac(options) then
      return row
    end

    if not _M.validate_entity_operation(row, name) then
      local err_t = db.errors:unauthorized_operation({
        username = ngx.ctx.rbac.user.name,
        action = _M.readable_action(ngx.ctx.rbac.action)
      })

      return nil, err_t
    end

    return row
  end)

  local function pre_upsert(entity, name, options)
    if skip_rbac(options) then
      return true
    end

    if not _M.validate_entity_operation(entity, name) then
      local err_t = db.errors:unauthorized_operation({
        username = ngx.ctx.rbac.user.name,
        action = _M.readable_action(ngx.ctx.rbac.action)
      })

      return nil, err_t
    end

    return true
  end

  local function post_upsert(row, name, options, ws_id, is_new)
    -- Handle updates
    if not is_new then
      return row
    end

    local _, err = _M.add_default_role_entity_permission(row, name)
    if err then
      local err_t = db.errors:database_error("failed to add entity permissions to current user")
      return nil, err_t
    end

    return row
  end

  register_hook("dao:upsert_by:pre", pre_upsert)
  register_hook("dao:upsert_by:post", post_upsert)

  register_hook("dao:upsert:pre", pre_upsert)
  register_hook("dao:upsert:post", post_upsert)

  register_hook("dao:delete_by:pre", function(entity, name, cascade_entities, options)
    if skip_rbac(options) then
      return true
    end

    if not _M.validate_entity_operation(entity, name) or
       not _M.check_cascade(cascade_entities, ngx.ctx.rbac) then

      -- operation or cascading not allowed
      local err_t = db.errors:unauthorized_operation({
        username = ngx.ctx.rbac.user.name,
        action = _M.readable_action(ngx.ctx.rbac.action)
      })

      return nil, err_t
    end

    return true
  end)

  register_hook("dao:delete_by:post", function(entity, name, _, ws_id, cascade_entities)
    local err = _M.delete_role_entity_permission(name, entity)
    if err then
      return nil, db.errors:database_error("could not delete Route relationship " ..
          "with Role: " .. err)
    end

    for _, cascade_entity in ipairs(cascade_entities or EMPTY_T) do
      local err = _M.delete_role_entity_permission(cascade_entity.dao.schema.table_name, cascade_entity.entity)
      if err then
        return nil, db.errors:database_error("could not delete Route relationship " ..
          "with Role: " .. err)
      end
    end

    return entity
  end)

  register_hook("dao:select:pre", function(pk, name, options)
    if skip_rbac(options) then
      return true
    end

    if not _M.validate_entity_operation(pk, name) then
      local err_t = db.errors:unauthorized_operation({
        username = ngx.ctx.rbac.user.name,
        action = _M.readable_action(ngx.ctx.rbac.action)
      })
      return nil, err_t
    end

    return true
  end)

  register_hook("dao:insert:post", function(row, name, options)
    -- if entity was created, insert it in the user's default role
    if not kong.db[name].schema.workspaceable then
      return row
    end

    if row then
      local _, err = _M.add_default_role_entity_permission(row, name)
      if err then
        local err_t = db.errors:database_error("failed to add entity permissions to current user")
        return nil, err_t
      end
    end

    if name == "rbac_users" then
      local _, err = _M.create_default_role(row, options and options.workspace)
      if err then
        return nil, "failed to create default role for '" .. row.name .. "'"
      end
    end

    return row
  end)

  register_hook("dao:update:pre", function(entity, name, options)
    if skip_rbac(options) then
      return entity
    end

    if not _M.validate_entity_operation(entity, name) then
      local err_t = db.errors:unauthorized_operation({
        username = ngx.ctx.rbac.user.name,
        action = _M.readable_action(ngx.ctx.rbac.action)
      })

      return nil, err_t
    end

    return entity
  end)

  register_hook("dao:delete:post", function(entity, name, options)
    local err = _M.delete_role_entity_permission(name, entity)
    if err then
      return nil, db.errors:database_error("could not delete entity relationship with Role: " .. err)
    end

    return entity
  end)

  register_hook("dao:iterator:post", function(entity, name, options)
    if skip_rbac(options) then
      return entity
    end

    return _M.validate_entity_operation(entity, name) and entity
  end)
end


local get_with_cache
do
  local function get_with_cache_fn(dao, id, workspace)
    local row, err = dao:select({ id = id }, { skip_rbac = true, workspace = workspace, show_ws_id = true  })
    if row then
      return row
    end
    return nil, err, -1
  end

  get_with_cache = function(entity, id, workspace)
    assert(workspace == null or (type(workspace) == "string" and workspace ~= "*"),
      "workspace must be an id (string uuid) or ngx.null to mean global")

    local dao = kong.db[entity]

    local cache_key = dao:cache_key(id)

    local result = kong.cache:get(cache_key, nil, get_with_cache_fn, dao, id, workspace)
    if result and not result.ws_id then
      kong.cache:invalidate(cache_key)
    end

    return kong.cache:get(cache_key, nil, get_with_cache_fn, dao, id, workspace)
  end

  _M.get_with_cache = get_with_cache
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
    show_ws_id = true,
    workspace = null,
  })

  if err then
    log(ngx.ERR, "error in retrieving user", err)
    return nil, err
  end

  if not user then
    log(ngx.DEBUG, "rbac_user not found")
    return nil, nil
  end

  return user
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



-- Return the permission of a key on a map in the given permission
-- bit. Also return a second result whether the entity permission was
-- explicitly set or absent
local function bitfield_check(map, key, bit)
  local keys = {
    key, -- exact match has priority
    "*", -- wildcard
  }

  for _, key in ipairs(keys) do
    -- first, verify negative permissions
    if map[key] and band(rshift(map[key], 4), bit) == bit then
      return false, true
    end

    -- then, positive permissions
    if map[key] and band(map[key], bit) == bit then
      return true, true
    end
  end

  return false, false
end


local function retrieve_role_relations(db, entity_name, role, opts)
  opts = opts or {}
  opts.show_ws_id = true
  opts.skip_rbac = true

  local res = {}
  for role, err in db[entity_name]:each_for_role({id = role.id}, nil, opts) do
    if err then
      return nil, err
    end

    table.insert(res, role)
  end

  return res
end


local function get_role_relations_cache(db, entity_name, role, opts)
  local cache = kong.cache

  local relationship_cache_key = db[entity_name]:cache_key(role.id)
  local res, err = cache:get(relationship_cache_key, nil,
                                          retrieve_role_relations,
                                          db,
                                          entity_name,
                                          role,
                                          opts)

  if err then
    return nil, err
  end

  return res
end


local function get_role_entities(db, role, opts)
  -- only cache when rbac entity is enabled to avoid unnecessary memory increase
  if kong.configuration and
    (kong.configuration.rbac == "both" or
    kong.configuration.rbac == "entity") then
    return get_role_relations_cache(db, "rbac_role_entities", role, opts)
  end

  return retrieve_role_relations(db, "rbac_role_entities", role, opts)
end

local function get_role_endpoints(db, role, opts)
  return get_role_relations_cache(db, "rbac_role_endpoints", role, opts)
end
_M.get_role_endpoints = get_role_endpoints


local function retrieve_group(dao, name)
  local entity, err = dao:select_by_name(name, { skip_rbac = true })

  if err then
    return nil, err
  end

  return entity
end


local function retrieve_roles_ids(db, user_id)
  local relationship_ids = {}
  for row, err in db.rbac_user_roles:each_for_user({id = user_id}, nil, {skip_rbac = true}) do
    if err then
      return nil, err
    end
    relationship_ids[#relationship_ids + 1] = row
  end

  return relationship_ids
end


local function retrieve_group_roles_ids(db, group_id)
  local relations = {}
  for row, err in db.group_rbac_roles:each_for_group({ id = group_id }, nil,
                                                     { skip_rbac = true,
                                                       workspace = null })
  do
    if err then
      return nil, err
    end
    relations[#relations + 1] = row
  end

  return relations
end


local function select_from_cache(dao, name, retrieve_entity)
  local cache_key = dao:cache_key(name)
  local entity, err = kong.cache:get(cache_key, nil, retrieve_entity, dao, name)

  if err then
    return nil, err
  end

  return entity
end


local function get_user_roles(db, user, workspace)
  assert(workspace == null or (type(workspace) == "string" and workspace ~= "*"),
    "workspace must be an id (string uuid) or ngx.null to mean global")

  if type(workspace) == "string" and not utils.is_valid_uuid(workspace) then
    local ws, err = workspaces.select_workspace_by_name_with_cache(workspace)
    if not ws then
      return nil, err
    end
    workspace = ws.id
  end

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

    local relationship, err = get_with_cache("rbac_roles", foreign_id, workspace)
    if err then
      kong.log.err("err retrieving relationship via id ", foreign_id, ": ", err)
      return nil, err
    end

    if relationship and (workspace == null or workspace == relationship.ws_id) then
      relationship_objs[#relationship_objs + 1] = relationship
    end
  end

  return relationship_objs
end
_M.get_user_roles = get_user_roles


function _M.get_groups_roles(db, groups)
  if not groups then
    return nil
  end

  local cache = kong.cache
  local relationship_objs = {}

  for _, group_name in pairs(groups) do
    if type(group_name) == "number" then
      group_name = tostring(group_name)
    end
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


      for i = 1, #relationship_ids do
        local rbac_role_id = relationship_ids[i]["rbac_role"].id

        local relationship, err = get_with_cache("rbac_roles", rbac_role_id, null)
        if err then
          kong.log.err("err retrieving rbac_role for id: ", rbac_role_id, ": ", err)
          return nil, err
        end

        relationship_objs[#relationship_objs + 1] = relationship
      end
    end
  end

  return relationship_objs
end


-- allows setting several roles simultaneously, minimizing database accesses
-- @returns true if the new roles were set successfully
-- @returns nil, errors_str, errors_array if there was 1 or more errors
local function set_user_roles(db, user, new_role_names, workspace)
  assert(utils.is_valid_uuid(workspace), "workspace must be an id (string uuid)")

  local existing_roles, err = get_user_roles(db, user, workspace)
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
      local opts = { workspace = workspace }
      local role = db.rbac_roles:select_by_name(new_role_name, opts)
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


local function get_role_users(db, role, workspace)
  assert(workspace == null or (type(workspace) == "string" and workspace ~= "*"),
    "workspace must be an id (string uuid) or ngx.null to mean global")

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
    local id = relationship_ids[i]["user"].id

    local relationship, err = get_with_cache("rbac_users", id, ngx.ctx.workspace)
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
      mask(role_entity.actions, role_entity.entity_id)
    end
  end

  -- assign all the positive bits first such that we dont have a case
  -- of an explicit positive overriding an explicit negative based on
  -- the order of iteration
  local positive_entities, negative_entities =  {}, {}
  for _, role in ipairs(roles) do
    local role_entities, err = get_role_entities(kong.db, role)
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
_M._resolve_role_entity_permissions = resolve_role_entity_permissions -- for tests only


local load_rbac_ctx


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

  local user, err = load_rbac_ctx(rbac_user)

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
  local reserved_tables = { "workspace*", "sessions", "keyring_meta", "keyring_keys" }
  for _, v in ipairs(reserved_tables) do
    if string.find(t, v) then
      return true
    end
  end

  return false
end


local function is_admin_api_request()
  local r = base.get_request()
  if not r then
    return false
  end

  return ngx.ctx.admin_api_request
end


-- helper: create default role and the corresponding user-role association
-- user: the rbac user entity
function _M.create_default_role(user, ws_id)
  local role, err
  local opts = { workspace = ws_id }

  -- try fetching the role; if it exists, use it
  role, err = kong.db.rbac_roles:select_by_name(user.name, opts)

  if err then
    return nil, err
  end

  -- if it doesn't exist, create it
  if not role then
    role, err = kong.db.rbac_roles:insert({
      name = user.name,
      comment = "Default user role generated for " .. user.name,
      is_default = true,
    }, opts)
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


-- helpers: delete the role no rbac_user has that role This is ment to
-- be used on default roles after deleting its main user. Previously
-- this function had to delete the rbac_user_role relationship. Now
-- it's managed by delete-cascade at dao level
function _M.remove_default_role_if_empty(default_role, workspace)
  assert(workspace == null or (type(workspace) == "string" and workspace ~= "*"),
    "workspace must be an id (string uuid) or ngx.null to mean global")

  -- get count of users still in the default role
  local users, err = get_role_users(kong.db, default_role, workspace)
  local n_users = #users
  if err then
    return nil, err
  end

  -- if count of users in role reached 0, delete it
  if n_users == 0 then
    local _, err = kong.db.rbac_roles:delete({
      id = default_role.id,
    }, { workspace = workspace })
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

  return kong.db.rbac_role_entities:insert({
    role = default_role,
    entity_id = entity[entity_id],
    entity_type = table_name,
    actions = bitfield_all_actions,
    negative = false,
    }, { workspace = null })
end
_M.add_default_role_entity_permission = add_default_role_entity_permission


-- remove role-entity permission: remove an entity from the role
-- should be called when entity is deleted or role is removed
local function delete_role_entity_permission(table_name, entity)
  local db = kong.db

  local schema = db[table_name] and db[table_name].schema

  local entity_id = schema.primary_key[1]
  if schema.fields[entity_id].type == "foreign" then
    entity_id = entity_id .. "_id"
  end

  db.rbac_role_entities:delete_role_entity_permission(entity[entity_id], table_name)

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


local function authorize_request_entity(map, id, action)
  return bitfield_check(map, id, action)
end
_M._authorize_request_entity = authorize_request_entity -- for tests only


function _M.validate_entity_operation(entity, table_name)
  -- rbac only applies to the admin api - ie, proxy side
  -- requests are not to be considered
  if not is_admin_api_request() then
    return true
  end

  -- rbac does not apply to "system tables" - e.g., many-to-many tables
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

  local pmap = rbac_ctx.entities_perms
  local action = rbac_ctx.action

  local schema = kong.db.daos[table_name].schema

  local entity_id = schema.primary_key[1]

  if schema.workspaceable then
    if not entity.ws_id then
      local db_entity = kong.db[table_name]:select({ id = entity_id },
        { skip_rbac = true, workspace = null, show_ws_id = true })
      if db_entity then
        entity = db_entity
      end
    end
  end

  -- default w permision to false. If an entity is not workspaceable,
  -- the perm_set(entity.ws_id) (that is nil) will be false. So `or`
  -- applies, therefore we make it a nop by setting it to false.
  local w, explicit_ws_perm = false
  if entity.ws_id then
    w, explicit_ws_perm = authorize_request_entity(pmap, entity.ws_id, action)
  end

  local e, explicit_e_perm = authorize_request_entity(pmap, entity[entity_id], action)

  --   Truth table of the rbac thingie.
  --   If a permission is false, we don't know if it's by omission of
  --   any permission over that entity (think there are 2 levels, ws
  --   and entities). perm_set uses the fact that we do have
  --   permissions or not on that entity to discern one or the other
  --   situation.
  -- w | e | ps(w) | ps(e)
  -- 0 | 0 | X     | X  => 0
  -- 0 | 1 | 1     | 1  => 0   <- for backward compat. negative prevails
  -- 0 | 1 | 0     | 1  => 1
  -- 1 | 0 | 1     | 0  => 1
  -- 1 | 0 | 1     | 1  => 0
  -- 1 | 1 | 1     | 1  => 1

  if (not w) and (not e) then
    return false
  elseif not entity.ws_id then
    -- Explicit case for non wsable entities so we don't rely on the
    -- unspecced effect that perm_set(x, nil) returns false.
    return e
  elseif explicit_ws_perm and explicit_e_perm then
    return w and e
  else
    return w or e
  end

end

-- XXX EE: This is mostly used for displays in the API. slash this out
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
    local endpoint_actions
    for _, role_endpoint in ipairs(roles_endpoints) do
      local workspace = role_endpoint.workspace
      endpoint_actions = nmap[workspace] or {}
      if not pmap[workspace] then
        pmap[workspace] = {}
      end

      -- store explicit negative bits adjacent to the positive bits in the mask
      local p = role_endpoint.actions
      if role_endpoint.negative then
        p = bor(p, lshift(p, 4))
      end

      local ws_prefix = ""
      if role_endpoint.endpoint ~= "*" then
        ws_prefix = "/" .. workspace
      end

      local endpoint = ws_prefix .. role_endpoint.endpoint
      endpoint_actions[endpoint] = endpoint_actions[endpoint] or {}
      for action, n in pairs(actions_bitfields) do
        if band(n, p) == n then
          local actions = endpoint_actions[endpoint][action] or {}
          actions["negative"] = actions["negative"] or role_endpoint.negative
          endpoint_actions[endpoint][action] = actions
        end
      end
      pmap[workspace][endpoint] = 0x0
      nmap[workspace] = endpoint_actions
    end

  end

  for ws, endpoints in pairs(pmap) do
    local endpoint_actions = nmap[ws] or {}
    for endpoint, _ in pairs(endpoints) do
      for action, negative in pairs(endpoint_actions[endpoint]) do
        if negative.negative then
          pmap[ws][endpoint] = bor(pmap[ws][endpoint],lshift(actions_bitfields[action], actions_bitfield_size))

        else
          pmap[ws][endpoint] = bor(pmap[ws][endpoint], actions_bitfields[action])
        end
      end
    end
  end


  return pmap, nmap
end
_M.resolve_role_endpoint_permissions = resolve_role_endpoint_permissions


function _M.readable_endpoints_permissions(roles)
  local map, nmap = resolve_role_endpoint_permissions(roles)

  for workspace in pairs(map) do
    local endpoint_actions = nmap[workspace] or {}
    for endpoint, _ in pairs(map[workspace]) do
      map[workspace][endpoint] = {
        actions = endpoint_actions[endpoint]
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
          if perm == 0 or band(rshift(perm, actions_bitfield_size), action) == action then
            return false
          end

          if band(perm, action) == action then
            return true
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
  local bin
  if kong.configuration and kong.configuration.fips then
    local sha256 = assert(digest.new("sha256"))
    bin = assert(sha256:final(rbac_token))
  else

    bin = ngx.sha1_bin(rbac_token)
  end

  return string.sub(to_hex(bin), 1, 5)
end
_M.get_token_ident = get_token_ident


local function update_user_token(user)
  assert(user.ws_id)

  ngx.log(ngx.DEBUG, "updating user token hash for credential ",
                     user.id)

  local ident = get_token_ident(user.user_token)
  local digest, err
  if kong.configuration and kong.configuration.fips then
    digest, err = secret.hash(user.user_token)
  else
    digest, err = bcrypt.digest(user.user_token, BCRYPT_COST_FACTOR)
  end
  if err then
    ngx.log(ngx.ERR, "error attempting to hash user token: ", err)
    return
  end

  local _, err = kong.db.rbac_users:update(
    { id = user.id }, { user_token = digest, user_token_ident = ident },
    { skip_rbac = true, workspace = user.ws_id }
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
function _M.retrieve_token_users(ident, k)
  local opts = { workspace = null, show_ws_id = true, skip_rbac = true }

  local users = {}
  if k == "user_token" then
    -- user_token is unique
    local user, err = kong.db.rbac_users:select_by_user_token(ident, opts)
    if err then
      return nil, err
    end

    if user and user.enabled then
      table.insert(users, user)
    end

  elseif k == "user_token_ident" then
    -- XXXCORE less efficient each() here because user_token_ident
    -- is not unique
    for user, err in kong.db.rbac_users:each(nil, opts) do
      if err then
        return nil, err
      end

      if user.enabled and user.user_token_ident == ident then
        table.insert(users, user)
      end
    end
  end

  return users
end


-- fetch from mlcache a list of rbac_user rows that may be associated with
-- the request's rbac token, by virtue of the token ident
local function get_token_users(rbac_token)
  local ident = get_token_ident(rbac_token)

  local cache_key = "rbac_user_token_ident:" .. ident

  local token_users, err = kong.cache:get(cache_key, nil,
                             _M.retrieve_token_users,
                             ident,
                             "user_token_ident")
  if err then
    return nil, err
  end

  return token_users
end

local bcrypt_verify_wrapped = function(have, want)
  local ok, err = bcrypt.verify(have, want)
  if ok then
    return want
  end

  -- note here we set ttl < 1 to skip negative cache
  -- this is to preserve the purpose of having bcrypt.
  -- If bcrypt is replaced, we should unset the ttl overriding
  -- and also cache negative hit as well.
  return ok, err, -1
end

-- for a list of rbac_users (possible user given the ident),
-- validate the rbac token digest
local function validate_rbac_token(token_users, rbac_token)
  local fips = kong.configuration and kong.configuration.fips
  local sha256 = digest.new("SHA256")
  for _, user in ipairs(token_users) do
    -- fast search to try bcrypt first
    if find(user.user_token, "$2b$", nil, true) then
      if fips then
        kong.log.warn("rbac wants to verify using bcrypt, which is disallowed in FIPS mode, will rehash")
      end
      -- We never clear the cache but set a 60s TTL; it's impossible to do without
      -- a seperate reverse index. We can replace this with a lrucache with uplimit
      -- or introduce a migration in rbac_user to include a reliable hash
      -- (like full SHA256 digest) of the token.
      local verify_pair_hash = to_hex(sha256:final(rbac_token)) .. "$" .. user.user_token
      sha256:reset()
      local cache_key = "rbac_user_token:bcrypt_verify:" .. verify_pair_hash
      local ok, err = kong.cache:get(cache_key, { ttl = 60 },
                                      bcrypt_verify_wrapped,
                                      rbac_token, user.user_token)

      if err then
        kong.log.warn("[rbac] error occured when bcrypt verifying RBAC token with cache", err)
      end

      if ok then
        return user, fips
      end

    elseif secret.verify(rbac_token, user.user_token) then
      return user, secret.needs_rehash(user.user_token)

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


load_rbac_ctx = function(rbac_user)
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
      token_users = _M.retrieve_token_users(rbac_token, "user_token")
    end

    local must_update
    user, must_update = validate_rbac_token(token_users, rbac_token)
    if must_update then
      update_user_token(user)
    end

    if not user then
      -- caller assumes this signature means no error and no valid user found
      return nil, nil
    end
  end

  local user_ws_scope, err = _M.find_all_ws_for_rbac_user(user, null)
  if err then
    kong.log.err(err)
    return kong.response.exit(500, { message = "An unexpected error occurred" })
  end

  if not user_ws_scope or #user_ws_scope == 0 then
    return kong.response.exit(401, {message = "Invalid RBAC credentials"})
  end

  local _roles = {}
  local _entities_perms = {}
  local _endpoints_perms = {}
  local group_roles, err = _M.get_groups_roles(kong.db, ngx.ctx.authenticated_groups)
  if err then
    kong.log.err("error getting groups roles", err)
    return kong.response.exit(500, { message = "An unexpected error occurred" })
  end

  for _, workspace in ipairs(user_ws_scope) do
    if workspace and workspace ~= null and workspace.name == '*' then
      workspace = null
    else
      workspace = workspace.id
    end

    local roles, err = get_user_roles(kong.db, user, workspace)
    if err then
      kong.log.err("error getting user roles", err)
      return kong.response.exit(500, { message = "An unexpected error occurred" })
    end

    roles = _M.merge_roles(roles, group_roles)

    if err then
      return nil, err
    end
    for _, role in pairs(roles) do
      _roles[#_roles + 1] = role
    end
  end

  local entities_perms = {}
  if kong.configuration and
    (kong.configuration.rbac == "both" or
    kong.configuration.rbac == "entity") then
    local err, _
    entities_perms, _, err = resolve_role_entity_permissions(_roles)
    if err then
      return nil, err
    end
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

function _M.validate_user(rbac_user)
  if kong.configuration.rbac == "off" then
    return
  end

  local rbac_ctx, err = get_rbac_user_info(rbac_user)
  if err then
    ngx.log(ngx.ERR, "[rbac] ", err)
    return kong.response.exit(500, { message = "An unexpected error occurred" })
  end

  -- if it's whitelisted, we don't care who the user is
  if whitelisted_endpoints[ngx.var.uri] then
    return true
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
                                            workspaces.get_workspace().name,
                                            route, route_name, rbac_ctx.action)
  if not ok then
    local err = fmt("%s, you do not have permissions to %s this resource",
                    rbac_ctx.user.name, readable_action(rbac_ctx.action))
    return kong.response.exit(403, { message = err })
  end
end

local function find_admin_by_username_or_id(username_or_id)
  if not username_or_id then
    return nil
  end

  local admin, err
  if utils.is_valid_uuid(username_or_id) then
    admin, err = kong.db.admins:select({ id = username_or_id })
    if err then
      return nil, err
    end
  end

  if not admin then
    admin, err = kong.db.admins:select_by_username(username_or_id)
    if err then
      return nil, err
    end
  end

  return admin
end

local function is_rbac_role_in_ctx(request)
  local rbac = ngx.ctx.rbac
  local rbac_roles_id_or_name = request.params.rbac_roles
  if rbac and rbac.roles then
    for _, role in ipairs(rbac.roles) do
      if role.id == rbac_roles_id_or_name or role.name == rbac_roles_id_or_name then
        return true
      end
    end
  end

  return false
end

-- these routes the admin should not update by themselves
local NOT_PERMIT_ROUTE = {}

NOT_PERMIT_ROUTE["/admins/:admin/roles"] = {
  handler = function(request)
    local rbac_user = ngx.ctx.rbac.user
    local name_or_id = request.params.admin
    local admin      = find_admin_by_username_or_id(name_or_id)
    if admin and admin.rbac_user and rbac_user.id == admin.rbac_user.id then
      return true
    end

    return false
  end,
  methods = { POST = true, DELETE = true },
  err = "the admin should not update their own roles",
}

NOT_PERMIT_ROUTE["/rbac/roles/:rbac_roles/endpoints"] = {
  handler = is_rbac_role_in_ctx,
  methods = { POST = true, },
  err = "the admin should not update their own roles",
}

NOT_PERMIT_ROUTE["/rbac/roles/:rbac_roles/endpoints/:workspace/*"] = {
  handler = is_rbac_role_in_ctx,
  methods = { PATCH = true, DELETE = true },
  err = "the admin should not update or delete their own endpoints",
}

-- should not delete their own roles
NOT_PERMIT_ROUTE["/rbac/roles/:rbac_roles"] = {
  handler = is_rbac_role_in_ctx,
  methods = { DELETE = true, },
  err = "the admin should not delete their own roles",
}

function _M.validate_permit_update(request)
  local route_name = request.route_name
  if route_name and stringx.startswith(route_name, "workspace_") then
    route_name = stringx.replace(route_name, "workspace_", "")
  end
  
  local route = NOT_PERMIT_ROUTE[route_name]
  if route then
    local method = request.req.method
    if route.methods[method] and route.handler(request) then
      return kong.response.exit(403, { message = route.err })
    end
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

  -- XXXCORE entities is cascade_entries in the DAO... this table does *not* have this shape!?
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
    for _, entity in ipairs(table_info.entities or EMPTY_T) do
      if not authorize_request_entity(rbac_ctx.entities_perms,
                                      entity[table_info.schema.primary_key[1]],
                                      rbac_ctx.action) then
        return false
      end
    end
  end

  return true
end

function _M.find_all_ws_for_rbac_user(rbac_user, workspace)
    -- get roles across all workspaces
  local roles, err = _M.get_user_roles(kong.db, rbac_user, workspace)
  if err then
    return nil, err
  end

  local group_roles, err = _M.get_groups_roles(kong.db, ngx.ctx.authenticated_groups)

  if err then
    return nil, err
  end

  roles = _M.merge_roles(roles, group_roles)

  local wss = {}
  local wsNameMap = {}

  local opts = { workspace = null, show_ws_id = true }
  for _, role in ipairs(roles) do
    for _, role_endpoint in ipairs(_M.get_role_endpoints(kong.db, role, opts)) do
      local wsName = role_endpoint.workspace
      if wsName == "*" then
        if not wsNameMap[wsName] then
          wss[#wss + 1] = { name = "*" }
          wsNameMap["*"] = true
        end
      else
        if not wsNameMap[wsName] then
          local ws = workspaces.select_workspace_by_name_with_cache(wsName)
          if ws then
            wsNameMap[wsName] = true
            ws.meta = nil
            wss[#wss + 1] = ws
          end
        end
      end
    end
  end

  local rbac_user_ws_id = assert(rbac_user.ws_id)
  local ws, err = workspaces.select_workspace_by_id_with_cache(rbac_user_ws_id)
  if not ws then
    return nil, err
  end
  ws.meta = nil

  -- hide the workspace associated with the admin's rbac_user most of the time,
  -- but if there is no known workspace or the only workspace is '*', mark it as
  -- belonging to the admin
  local numberOfWorkspaces = tablex.size(wsNameMap)
  if not wsNameMap[ws.name] and
    ((numberOfWorkspaces == 1 and next(wsNameMap) == '*') or numberOfWorkspaces == 0)
  then
    ws.is_admin_workspace = true
    wss[#wss + 1] = ws
  end

  return wss
end

do
  local reports = require "kong.reports"
  local counters = require "kong.workspaces.counters"
  local rbac_users_count = function()
    local counts, err = counters.entity_counts()
    if err then
      kong.log.warn("failed to get count of RBAC users: ", err)
      return nil
    end

    return counts.rbac_users or 0
  end

  reports.add_ping_value("rbac_users", rbac_users_count)
end


return _M
