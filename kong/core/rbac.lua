local _M = {}

local utils      = require "kong.tools.utils"
local singletons = require "kong.singletons"
local bit        = require "bit"
local tab_clear  = require "table.clear"

local band = bit.band
local bxor = bit.bxor
local bor  = bit.bor
local fmt  = string.format


local function log(lvl, ...)
  ngx.log(lvl, "[rbac] ", ...)
end


local actions_bitfields = {
  read   = 0x01,
  create = 0x02,
  update = 0x04,
  delete = 0x08,
}
_M.actions_bitfields = actions_bitfields


local resource_bitfields = {}
_M.resource_bitfields = resource_bitfields


local figure_action
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

  _M.figure_action = figure_action
end


local route_resources = {}
local resource_routes = {}
_M.route_resources = route_resources
_M.resource_routes = resource_routes


local function load_resource_bitfields(dao_factory)
  tab_clear(resource_bitfields)

  local rows, err = dao_factory.rbac_resources:find_all()
  if err then
    error("Error in retrieving RBAC resource entries: " .. err)
  end

  table.sort(rows, function(a, b) return a.bit_pos < b.bit_pos end)

  for i = 1, #rows do
    local idx = rows[i].bit_pos
    local resource = rows[i].name

    resource_bitfields[idx] = resource
    resource_bitfields[resource] = 2 ^ (idx - 1)
  end
end
_M.load_resource_bitfields = load_resource_bitfields


local function register_resource(resource, dao_factory)
  -- clear and reload our bitfields so we make sure are inserting the correct
  -- bit_pos
  load_resource_bitfields(dao_factory)

  local idx = #resource_bitfields + 1

  resource_bitfields[idx] = resource
  resource_bitfields[resource] = 2 ^ (idx - 1)

  local ok, err = dao_factory.rbac_resources:insert({
    id = utils.uuid(),
    name = resource,
    bit_pos = idx,
  })
  if not ok then
    return nil, err
  end

  return ok
end
_M.register_resource = register_resource


function _M.register_resource_route(route_path, resource)
  if not resource_bitfields[resource] then
    error("Resource '" .. resource .. "' not previous defined in " ..
          "rbac_resources table", 2)
  end

  if route_resources[route_path] then
    error("Resource route " .. route_path .. " already exists", 2)
  end

  log(ngx.INFO, "registering RBAC resource ", route_path, " as ",
      resource)

  route_resources[route_path] = resource

  if not resource_routes[resource] then
    resource_routes[resource] = {}
  end

  table.insert(resource_routes[resource], route_path)
end


-- fetch the id pair mapping of related objects from the database
local function retrieve_relationship_ids(entity_id, entity_name, factory_key)
  local relationship_ids, err = singletons.dao[factory_key]:find_all({
    [entity_name .. "_id"] = entity_id,
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


local function retrieve_user(user_token)
  local user, err = singletons.dao.rbac_users:find_all({
    user_token = user_token,
  })
  if err then
    log(ngx.ERR, "error in retrieving user from token: ", err)
    return nil, err
  end

  return user[1]
end


local function get_user(user_token)
  local cache_key = singletons.dao.rbac_users:cache_key(user_token)
  local user, err = singletons.cache:get(cache_key, nil,
                                         retrieve_user, user_token)

  if err then
    return nil, err
  end

  return user
end


local function build_permissions_map(user, dao_factory)
  local roles, err = entity_relationships(dao_factory, user, "user", "role")
  if err then
    return nil, err
  end

  local permissions, neg_permissions = {}, {}

  for i = 1, #roles do
    local p, err = entity_relationships(dao_factory, roles[i], "role", "perm")
    if err then
      return nil, err
    end

    for j = 1, #p do
      if p[j].negative == false or not p[j].negative then
        permissions[#permissions + 1] = p[j]

      else
        neg_permissions[#neg_permissions + 1] = p[j]
      end
    end
  end

  local pmap = {}

  for i = 1, #permissions do
    local p = permissions[i]

    for j, _ in ipairs(resource_bitfields) do
      local k = resource_bitfields[j]
      local n = resource_bitfields[k]

      if band(n, p.resources) == n then
        pmap[k] = bor(p.actions, pmap[k] or 0x0)
      end
    end
  end

  for i = 1, #neg_permissions do
    local p = neg_permissions[i]

    for j, _ in ipairs(resource_bitfields) do
      local k = resource_bitfields[j]
      local n = resource_bitfields[k]

      if band(n, p.resources) == n then
        pmap[k] = band(pmap[k], bxor(p.actions, pmap[k] or 0x0))
      end
    end
  end

  return pmap
end
_M.build_permissions_map = build_permissions_map


local function check(map, resource, action)
  return map[resource] and band(map[resource], action) == action or false
end


function _M.validate(token, route, method, dao_factory)
  if not token then
    return false
  end

  local user, err = get_user(token)
  if err then
    return nil, err
  end

  if not user then
    return false
  end

  local map, err = build_permissions_map(user, dao_factory)
  if err then
    return nil, err
  end

  local action = figure_action(method)
  local resource = route_resources[route]

  return check(map, resource, action)
end


return _M
