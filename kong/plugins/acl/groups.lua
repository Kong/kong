local tablex = require "pl.tablex"


local EMPTY = tablex.readonly {}


local kong = kong
local type = type
local mt_cache = { __mode = "k" }
local setmetatable = setmetatable
local consumer_groups_cache = setmetatable({}, mt_cache)
local consumer_in_groups_cache = setmetatable({}, mt_cache)


local function load_groups_into_memory(consumer_pk)
  local groups = {}
  local len    = 0

  for row, err in kong.db.acls:each_for_consumer(consumer_pk) do
    if err then
      return nil, err
    end
    len = len + 1
    groups[len] = row
  end

  return groups
end


--- Returns the database records with groups the consumer belongs to
-- @param consumer_id (string) the consumer for which to fetch the groups it belongs to
-- @return table with group records (empty table if none), or nil+error
local function get_consumer_groups_raw(consumer_id)
  local cache_key = kong.db.acls:cache_key(consumer_id)
  local raw_groups, err = kong.cache:get(cache_key, nil,
                                         load_groups_into_memory,
                                         { id = consumer_id })
  if err then
    return nil, err
  end

  -- use EMPTY to be able to use it as a cache key, since a new table would
  -- immediately be collected again and not allow for negative caching.
  return raw_groups or EMPTY
end


--- Returns a table with all group names a consumer belongs to.
-- The table will have an array part to iterate over, and a hash part
-- where each group name is indexed by itself. Eg.
-- {
--   [1] = "users",
--   [2] = "admins",
--   users = "users",
--   admins = "admins",
-- }
-- If there are no groups defined, it will return an empty table
-- @param consumer_id (string) the consumer for which to fetch the groups it belongs to
-- @return table with groups (empty table if none) or nil+error
local function get_consumer_groups(consumer_id)
  local raw_groups, err = get_consumer_groups_raw(consumer_id)
  if not raw_groups then
    return nil, err
  end

  local groups = consumer_groups_cache[raw_groups]
  if not groups then
    groups = {}
    consumer_groups_cache[raw_groups] = groups
    for i = 1, #raw_groups do
      local group = raw_groups[i].group
      groups[i] = group
      groups[group] = group
    end
  end
  return groups
end


--- checks whether a consumer-group-list is part of a given list of groups.
-- @param groups_to_check (table) an array of group names. Note: since the
-- results will be cached by this table, always use the same table for the
-- same set of groups!
-- @param consumer_groups (table) list of consumer groups (result from
-- `get_consumer_groups`)
-- @return (boolean) whether the consumer is part of any of the groups.
local function consumer_in_groups(groups_to_check, consumer_groups)
  -- 1st level cache on "groups_to_check"
  local result1 = consumer_in_groups_cache[groups_to_check]
  if result1 == nil then
    result1 = setmetatable({}, mt_cache)
    consumer_in_groups_cache[groups_to_check] = result1
  end

  -- 2nd level cache on "consumer_groups"
  local result2 = result1[consumer_groups]
  if result2 ~= nil then
    return result2
  end

  -- not found, so validate and populate 2nd level cache
  result2 = false
  for i = 1, #groups_to_check do
    if consumer_groups[groups_to_check[i]] then
      result2 = true
      break
    end
  end

  result1[consumer_groups] = result2

  return result2
end


--- Gets the currently identified consumer for the request.
-- Checks both consumer and if not found the credentials.
-- @return consumer_id (string), or alternatively `nil` if no consumer was
-- authenticated.
local function get_current_consumer_id()
  return (kong.client.get_consumer() or EMPTY).id or
         (kong.client.get_credential() or EMPTY).consumer_id
end


--- Returns a table with all group names.
-- The table will have an array part to iterate over, and a hash part
-- where each group name is indexed by itself. Eg.
-- {
--   [1] = "users",
--   [2] = "admins",
--   users = "users",
--   admins = "admins",
-- }
-- If there are no authenticated_groups defined, it will return nil
-- @return table with groups or nil
local function get_authenticated_groups()
  local authenticated_groups = kong.ctx.shared.authenticated_groups
  if type(authenticated_groups) ~= "table" then
    authenticated_groups = ngx.ctx.authenticated_groups
    if authenticated_groups == nil then
      return nil
    end

    if type(authenticated_groups) ~= "table" then
      kong.log.warn("invalid authenticated_groups, a table was expected")
      return nil
    end
  end

  local groups = {}
  for i = 1, #authenticated_groups do
    groups[i] = authenticated_groups[i]
    groups[authenticated_groups[i]] = authenticated_groups[i]
  end

  return groups
end


--- checks whether a group-list is part of a given list of groups.
-- @param groups_to_check (table) an array of group names.
-- @param groups (table) list of groups (result from
-- `get_authenticated_groups`)
-- @return (boolean) whether the authenticated group is part of any of the
-- groups.
local function group_in_groups(groups_to_check, groups)
  for i = 1, #groups_to_check do
    if groups[groups_to_check[i]] then
      return true
    end
  end
end


return {
  get_current_consumer_id = get_current_consumer_id,
  get_consumer_groups = get_consumer_groups,
  get_authenticated_groups = get_authenticated_groups,
  consumer_in_groups = consumer_in_groups,
  group_in_groups = group_in_groups,
}
