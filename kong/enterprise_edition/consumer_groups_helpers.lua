-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local kong = kong
local utils              = require "kong.tools.utils"


local function load_consumer_group_into_memory(consumer_group_pk_or_name)
  local grp
  if not utils.is_valid_uuid(consumer_group_pk_or_name) then
    grp = kong.db.consumer_groups:select_by_name(consumer_group_pk_or_name)
  else
    grp = kong.db.consumer_groups:select({id=consumer_group_pk_or_name})
  end
  return grp
end

local function get_consumer_group(consumer_group_pk_or_name)
  local cache_key = kong.db.consumer_groups:cache_key(consumer_group_pk_or_name)
  local grp = kong.cache:get(cache_key, nil,
                                           load_consumer_group_into_memory,
                                           consumer_group_pk_or_name)
  return grp

end

local function load_consumer_group_config(consumer_group_pk)
  local grpcfg
    for row in kong.db.consumer_group_plugins:each() do
      if row.consumer_group.id == consumer_group_pk then
        if row.name == "rate-limiting-advanced" then
          grpcfg = row
        end
      end
    end
    return grpcfg
  end


local function get_consumer_group_config(consumer_group_pk)
  local cache_key = kong.db.consumer_group_plugins:cache_key(consumer_group_pk)
  local grpcfg = kong.cache:get(cache_key,nil, load_consumer_group_config, consumer_group_pk)
  return grpcfg
end

local function get_consumers_in_group(consumer_group_pk)
  local consumers = {}
  local len = 0
  for row in kong.db.consumer_group_consumers:each() do
    if consumer_group_pk == row.consumer_group.id then
      len = len + 1
      consumers[len] = kong.db.consumers:select(row.consumer)
    end
  end
  if len == 0 then
    return nil
  end
  return consumers
end

local function is_consumer_in_group(consumer_pk, consumer_group_pk_or_name)
  local relation = kong.db.consumer_group_consumers:select(
    {
      consumer = {id = consumer_pk},
      consumer_group = {id = get_consumer_group(consumer_group_pk_or_name).id},
    }
    )
    if relation then
      return true
    end
    return false
end

local function delete_consumer_in_group(consumer_pk, consumer_group_pk_or_name)
  if is_consumer_in_group(consumer_pk, consumer_group_pk_or_name) then
    kong.db.consumer_group_consumers:delete(
      {
        consumer_group = {id = get_consumer_group(consumer_group_pk_or_name).id},
        consumer = { id = consumer_pk,},
      }
    )
    return true
  else
    return false
  end
end

local function get_plugins_in_group(consumer_group_pk)
  local plugins = {}
  local len = 0
  for row in kong.db.consumer_group_plugins:each() do
    if consumer_group_pk == row.consumer_group.id then
      len = len + 1
      plugins[len] = row
    end
  end
  if len == 0 then
    return nil
  end
  return plugins
end

local function select_by_username_or_id(db, key)
  local entity
  if not utils.is_valid_uuid(key) then
    entity = db:select_by_username(key)
  else
    entity = db:select({ id = key })
  end
  return entity
end

local function get_groups_by_consumer(consumer_pk)
  local groups = {}
  local len = 0
  for row in kong.db.consumer_group_consumers:each() do
    if consumer_pk == row.consumer.id then
      len = len + 1
      groups[len] = get_consumer_group(row.consumer_group.id)
    end
  end
  if len == 0 then
    return nil
  end
  return groups
end

return {
    get_consumer_group = get_consumer_group,
    get_consumer_group_config = get_consumer_group_config,
    get_consumers_in_group = get_consumers_in_group,
    delete_consumer_in_group = delete_consumer_in_group,
    get_groups_by_consumer = get_groups_by_consumer,
    is_consumer_in_group = is_consumer_in_group,
    get_plugins_in_group = get_plugins_in_group,
    select_by_username_or_id = select_by_username_or_id,
  }