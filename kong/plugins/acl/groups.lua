local tablex = require "pl.tablex"


local EMPTY = tablex.readonly {}


local kong = kong
local mt_cache = { __mode = "k" }
local setmetatable = setmetatable
local kongsumer_groups_cache = setmetatable({}, mt_cache)
local kongsumer_in_groups_cache = setmetatable({}, mt_cache)


local function load_groups_into_memory(kongsumer_pk)
  local groups = {}
  local len    = 0

  for row, err in kong.db.acls:each_for_kongsumer(kongsumer_pk, 1000) do
    if err then
      return nil, err
    end
    len = len + 1
    groups[len] = row
  end

  return groups
end


--- Returns the database records with groups the kongsumer belongs to
-- @param conumer_id (string) the kongsumer for which to fetch the groups it belongs to
-- @return table with group records (empty table if none), or nil+error
local function get_kongsumer_groups_raw(kongsumer_id)
  local cache_key = kong.db.acls:cache_key(kongsumer_id)
  local raw_groups, err = kong.cache:get(cache_key, nil,
                                         load_groups_into_memory,
                                         { id = kongsumer_id })
  if err then
    return nil, err
  end

  -- use EMPTY to be able to use it as a cache key, since a new table would
  -- immediately be collected again and not allow for negative caching.
  return raw_groups or EMPTY
end


--- Returns a table with all group names a kongsumer belongs to.
-- The table will have an array part to iterate over, and a hash part
-- where each group name is indexed by itself. Eg.
-- {
--   [1] = "users",
--   [2] = "admins",
--   users = "users",
--   admins = "admins",
-- }
-- If there are no groups defined, it will return an empty table
-- @param conumer_id (string) the kongsumer for which to fetch the groups it belongs to
-- @return table with groups (empty table if none) or nil+error
local function get_kongsumer_groups(kongsumer_id)
  local raw_groups, err = get_kongsumer_groups_raw(kongsumer_id)
  if not raw_groups then
    return nil, err
  end

  local groups = kongsumer_groups_cache[raw_groups]
  if not groups then
    groups = {}
    kongsumer_groups_cache[raw_groups] = groups
    for i = 1, #raw_groups do
      local group = raw_groups[i].group
      groups[i] = group
      groups[group] = group
    end
  end
  return groups
end


--- checks whether a kongsumer-group-list is part of a given list of groups.
-- @param groups_to_check (table) an array of group names. Note: since the
-- results will be cached by this table, always use the same table for the
-- same set of groups!
-- @param kongsumer_groups (table) list of kongsumer groups (result from
-- `get_kongsumer_groups`)
-- @return (boolean) whether the kongsumer is part of any of the groups.
local function kongsumer_in_groups(groups_to_check, kongsumer_groups)
  -- 1st level cache on "groups_to_check"
  local result1 = kongsumer_in_groups_cache[groups_to_check]
  if result1 == nil then
    result1 = setmetatable({}, mt_cache)
    kongsumer_in_groups_cache[groups_to_check] = result1
  end

  -- 2nd level cache on "kongsumer_groups"
  local result2 = result1[kongsumer_groups]
  if result2 ~= nil then
    return result2
  end

  -- not found, so validate and populate 2nd level cache
  result2 = false
  for i = 1, #groups_to_check do
    if kongsumer_groups[groups_to_check[i]] then
      result2 = true
      break
    end
  end

  result1[kongsumer_groups] = result2

  return result2
end


--- checks whether a kongsumer is part of the gieven list of groups
-- @param groups_to_check (table) an array of group names. Note: since the
-- results will be cached by this table, always use the same table for the
-- same set of groups!
-- @param kongsumer_id (string) id of kongsumer to verify
local function kongsumer_id_in_groups(groups_to_check, kongsumer_id)
  local kongsumer_groups, err = get_kongsumer_groups(kongsumer_id)
  if not kongsumer_groups then
    return nil, err
  end

  return kongsumer_in_groups(groups_to_check, kongsumer_groups)
end


--- Gets the currently identified kongsumer for the request.
-- Checks both kongsumer and if not found the credentials.
-- @return kongsumer_id (string), or alternatively `nil` if no kongsumer was
-- authenticated.
local function get_current_kongsumer_id()
  return (kong.client.get_kongsumer() or EMPTY).id or
         (kong.client.get_credential() or EMPTY).kongsumer_id
end


return {
  get_kongsumer_groups = get_kongsumer_groups,
  kongsumer_in_groups = kongsumer_in_groups,
  kongsumer_id_in_groups = kongsumer_id_in_groups,
  get_current_kongsumer_id = get_current_kongsumer_id,
}
