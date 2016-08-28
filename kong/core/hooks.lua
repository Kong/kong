local events = require "kong.core.events"
local cache = require "kong.tools.database_cache"
local utils = require "kong.tools.utils"
local singletons = require "kong.singletons"
local pl_stringx = require "pl.stringx"

local function invalidate_plugin(entity)
  cache.delete(cache.plugin_key(entity.name, entity.api_id, entity.consumer_id))
end

local function invalidate(message_t)
  if message_t.collection == "consumers" then
    cache.delete(cache.consumer_key(message_t.entity.id))
  elseif message_t.collection == "apis" then
    if message_t.entity then
      cache.delete(cache.api_key(message_t.entity.id))
    end
    cache.delete(cache.all_apis_by_dict_key())
  elseif message_t.collection == "plugins" then
    -- Handles both the update and the delete
    invalidate_plugin(message_t.old_entity and message_t.old_entity or message_t.entity)
  end
end

local function get_cluster_members()
  local members, err = singletons.serf:members()
  if err then
    return nil, err
  else
    return members
  end
end

local function retrieve_member_address(name)
  local members, err = get_cluster_members()
  if err then
    return nil, err
  else
    for _, member in ipairs(members) do
      if member.name == name then
        return member.addr
      end
    end
  end
end

local function parse_member(member_str)
  if member_str and utils.strip(member_str) ~= "" then
    local result = {}
    local index = 1
    for v in member_str:gmatch("%S+") do
      if index == 1 then
        result.name = v
      elseif index == 2 then
        local addr, err = retrieve_member_address(result.name)
        if err then
          return nil, err
        end
        result.cluster_listening_address = addr
      end
      index = index + 1
    end
    return result
  end
end

local function member_leave(s_node)
  local member, err = parse_member(s_node)
  if err then
    ngx.log(ngx.ERR, err)
    return
  end

  local _, err = singletons.dao.nodes:delete({
    name = member.name
  })
  if err then
    ngx.log(ngx.ERR, tostring(err))
  end
end

local function member_update(s_node, is_reap)
  local member, err = parse_member(s_node)
  if err then
    ngx.log(ngx.ERR, err)
    return
  end

  local nodes, err = singletons.dao.nodes:find_all {
    name = member.name
  }
  if err then
    ngx.log(ngx.ERR, tostring(err))
    return
  end

  if #nodes == 1 then
    local node = nodes[1]
    node.cluster_listening_address = member.cluster_listening_address
    local _, err = singletons.dao.nodes:update(node, node)
    if err then
      ngx.log(ngx.ERR, tostring(err))
      return
    end
  end

  if is_reap and singletons.dao.nodes:count() > 1 then
    -- Purge the cache when a failed node re-appears
    cache.delete_all()
  end
end

local function member_join(s_node)
  local member, err = parse_member(s_node)
  if err then
    ngx.log(ngx.ERR, err)
    return
  end

  local nodes, err = singletons.dao.nodes:find_all {
    name = member.name
  }
  if err then
    ngx.log(ngx.ERR, tostring(err))
    return
  end

  if #nodes == 1 then -- Update
    member_update(s_node)
  elseif #nodes > 1 then
    error("Inconsistency error. More than one node found with name "..member.name)
  end

  -- Purge the cache when a new node joins
  local members, err = get_cluster_members()
  if err then
    ngx.log(ngx.ERR, err)
  elseif #members > 1 then -- If it's only one node, no need to delete the cache
    cache.delete_all()
  end
end

return {
  [events.TYPES.ENTITY_UPDATED] = function(message_t)
    invalidate(message_t)
  end,
  [events.TYPES.ENTITY_DELETED] = function(message_t)
    invalidate(message_t)
  end,
  [events.TYPES.ENTITY_CREATED] = function(message_t)
    invalidate(message_t)
  end,
  [events.TYPES.CLUSTER_PROPAGATE] = function(message_t)
    singletons.serf:event(message_t)
  end,
  [events.TYPES["MEMBER-JOIN"]] = function(message_t)
    -- Sometimes multiple nodes are sent at once
    local members = pl_stringx.splitlines(message_t.entity)
    for _, member in ipairs(members) do
      member_join(member)
    end
  end,
  [events.TYPES["MEMBER-LEAVE"]] = function(message_t)
    -- Sometimes multiple nodes are sent at once
    local members = pl_stringx.splitlines(message_t.entity)
    for _, member in ipairs(members) do
      member_leave(member)
    end
  end,
  [events.TYPES["MEMBER-FAILED"]] = function(message_t)
    -- Sometimes multiple nodes are sent at once
    local members = pl_stringx.splitlines(message_t.entity)
    for _, member in ipairs(members) do
      member_update(member)
    end
  end,
  [events.TYPES["MEMBER-UPDATE"]] = function(message_t)
    -- Sometimes multiple nodes are sent at once
    local members = pl_stringx.splitlines(message_t.entity)
    for _, member in ipairs(members) do
      member_update(member)
    end
  end,
  [events.TYPES["MEMBER-REAP"]] = function(message_t)
    -- Sometimes multiple nodes are sent at once
    local members = pl_stringx.splitlines(message_t.entity)
    for _, member in ipairs(members) do
      member_update(member, true)
    end
  end
}
