local events = require "kong.core.events"
local cache = require "kong.tools.database_cache"
local stringy = require "stringy"
local cjson = require "cjson"
local Serf = require "kong.cli.services.serf"

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
  local serf = require("kong.cli.services.serf")(configuration)
  local res, err = serf:invoke_signal("members", { ["-format"] = "json" })
  if err then
    ngx.log(ngx.ERR, err)
  else
    return cjson.decode(res).members
  end
end

local function retrieve_member_address(name)
  local members = get_cluster_members()
  for _, member in ipairs(members) do
    if member.name == name then
      return member.addr
    end
  end
end

local function parse_member(member_str)
  if member_str and stringy.strip(member_str) ~= "" then
    local result = {}
    local index = 1
    for v in member_str:gmatch("%S+") do
      if index == 1 then
        result.name = v
      elseif index == 2 then
        result.cluster_listening_address = retrieve_member_address(result.name)
      end
      index = index + 1
    end
    return result
  end
end

local function member_leave(message_t)
  local member = parse_member(message_t.entity)

  local _, err = dao.nodes:delete({
    name = member.name
  })
  if err then
    ngx.log(ngx.ERR, tostring(err))
  end
end

local function member_update(message_t, is_reap)
  local member = parse_member(message_t.entity)

  local nodes, err = dao.nodes:find_by_keys({
    name = member.name
  })
  if err then
    ngx.log(ngx.ERR, tostring(err))
    return
  end

  if #nodes == 1 then
    local node = table.remove(nodes, 1)
    node.cluster_listening_address = member.cluster_listening_address
    local _, err = dao.nodes:update(node)
    if err then
      ngx.log(ngx.ERR, tostring(err))
      return
    end
  end

  if is_reap and dao.nodes:count_by_keys({}) > 1 then
    -- Purge the cache when a failed node re-appears 
    cache.delete_all()
  end
end

local function member_join(message_t)
  local member = parse_member(message_t.entity)

  local nodes, err = dao.nodes:find_by_keys({
    name = member.name
  })
  if err then
    ngx.log(ngx.ERR, tostring(err))
    return
  end

  if #nodes == 0 then -- Insert
    local _, err = dao.nodes:insert({
      name = stringy.strip(member.name),
      cluster_listening_address = stringy.strip(member.cluster_listening_address)
    })
    if err then
      ngx.log(ngx.ERR, tostring(err))
      return
    end
  elseif #nodes == 1 then -- Update
    member_update(message_t)
  else
    error("Inconsistency error. More than one node found with name "..member.name)
  end

  -- Purge the cache when a new node joins
  if #get_cluster_members() > 1 then -- If it's only one node, no need to delete the cache
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
    local serf = Serf(configuration)
    local ok, err = serf:event(message_t)
    if not ok then
      ngx.log(ngx.ERR, err)
    end
  end,
  [events.TYPES["MEMBER-JOIN"]] = function(message_t)
    member_join(message_t)
  end,
  [events.TYPES["MEMBER-LEAVE"]] = function(message_t)
    member_leave(message_t)
  end,
  [events.TYPES["MEMBER-FAILED"]] = function(message_t)
    member_update(message_t)
  end,
  [events.TYPES["MEMBER-UPDATE"]] = function(message_t)
    member_update(message_t)
  end,
  [events.TYPES["MEMBER-REAP"]] = function(message_t)
    member_update(message_t, true)
  end
}