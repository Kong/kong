local kong = kong
local consumers = {}

local function load_group_into_memory(consumer_group_name)

  local grp, _, err_t = kong.db.consumer_groups:select_by_name(consumer_group_name)
    if not grp or err_t then
      return nil
    end
  return grp
  end

local function get_consumer_group(consumer_group_name)
    local cache_key = kong.db.consumer_groups:cache_key(consumer_group_name)
    local grp, err = kong.cache:get(cache_key, nil,
                                           load_group_into_memory,
                                           consumer_group_name)
    if err then
      return nil, err
    end

    if grp then
        return grp
    end

    return nil

end

local function load_group_config(consumer_group_id)
  local grpcfg
    for row in kong.db.consumer_group_plugins:each() do
      if row.consumer_group.id == consumer_group_id then
        if row.name == "rate-limiting-advanced" then
          grpcfg = row
        end
      end
    end
    if not grpcfg then
      return nil
    end
    return grpcfg
  end


local function get_consumer_group_config(consumer_group_id)
    local cache_key = kong.db.consumer_group_plugins:cache_key(consumer_group_id)
    local grpcfg, err = kong.cache:get(cache_key,nil, load_group_config, consumer_group_id)
    if err then
      return nil, err
    end

    if grpcfg then
      return grpcfg
    end

    return nil
end

local function get_consumers_in_group(consumer_group_pk)
  local len = 0
  for row, err in kong.db.consumer_group_consumers:each() do
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

local function is_consumer_in_group(consumer_pk, consumer_group_name)
  local relation = kong.db.consumer_group_consumers:select(
    {
      consumer = {id = consumer_pk},
      consumer_group = {id = get_consumer_group(consumer_group_name).id},
    }
    )
    if relation then
      return true
    end
    return false
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

return {
    get_consumer_group = get_consumer_group,
    get_consumer_group_config = get_consumer_group_config,
    get_consumers_in_group = get_consumers_in_group,
    is_consumer_in_group = is_consumer_in_group,
    get_plugins_in_group = get_plugins_in_group,
  }