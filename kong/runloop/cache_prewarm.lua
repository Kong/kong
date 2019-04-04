local constants = require "kong.constants"


local CORE_ENTITIES = {}
do
  for _, entity_name in ipairs(constants.CORE_ENTITIES) do
    CORE_ENTITIES[entity_name] = true
  end
end

local tostring = tostring
local math = math
local ngx = ngx


local cache_prewarm = {}


local never_called = function()
  error("this should never be called as the L2 should already be warmed")
end


local function cache_set(cache, key, value)
  local ok, err = cache.safe_set(cache, key, value)
  if not ok then
    return nil, err
  end

  -- NOTE: this is just for warming up L1
  -- We don't do the same for cache_add because it isn't guaranteed there
  return cache.get(cache, key, nil, never_called)
end


local function cache_add(cache, key, value)
  local ok, err = cache.safe_add(cache, key, value)
  -- ignore this case - we don't want to override a value if it's already there
  if not ok and err == "exists" then
    return true
  end
  return ok, err
end


local function write_entity_in_cache(entity_name, dao, entity)
  local cache = kong.cache
  local get_key = dao.cache_key
  local key

  if entity_name ~= "plugins" then
    key = get_key(dao, entity)
    return cache_set(cache, key, entity)
  end
  -- Else, we're dealing with a plugin.
  -- Fill up cache both positively and negatively as much as possible

  local plugin_name = entity.name
  if not plugin_name then
    return nil, "Attempted to prewarm a plugin without name"
  end

  local route_id = nil
  if not entity.no_route and entity.route then
    route_id = entity.route.id
  end
  local service_id = nil
  if not entity.no_service and entity.service then
    service_id = entity.service.id
  end
  local consumer_id = nil
  if not entity.no_consumer and entity.consumer then
    consumer_id = entity.consumer.id
  end

  local ok, err
  if route_id and service_id and consumer_id then
    key = get_key(dao, plugin_name, route_id, service_id, consumer_id)
    ok, err = cache_set(cache, key, entity)
    if not ok then
      return nil, err
    end

    key = get_key(dao, plugin_name, route_id, service_id, nil)
    ok, err = cache_add(cache, key, nil)
    if not ok then
      return nil, err
    end

    key = get_key(dao, plugin_name, route_id, nil, consumer_id)
    ok, err = cache_add(cache, key, nil)
    if not ok then
      return nil, err
    end

    key = get_key(dao, plugin_name, nil, service_id, consumer_id)
    ok, err = cache_add(cache, key, nil)
    if not ok then
      return nil, err
    end

    key = get_key(dao, plugin_name, route_id, service_id, nil)
    ok, err = cache_add(cache, key, nil)
    if not ok then
      return nil, err
    end

    key = get_key(dao, plugin_name, nil, nil, consumer_id)
    ok, err = cache_add(cache, key, nil)
    if not ok then
      return nil, err
    end

    key = get_key(dao, plugin_name, route_id, nil, nil)
    ok, err = cache_add(cache, key, nil)
    if not ok then
      return nil, err
    end

    key = get_key(dao, plugin_name, nil, service_id, nil)
    ok, err = cache_add(cache, key, nil)
    if not ok then
      return nil, err
    end

    key = get_key(dao, plugin_name, nil, nil, nil)
    ok, err = cache_add(cache, key, nil)
    if not ok then
      return nil, err
    end

    return true
  end

  if route_id and consumer_id then
    key = get_key(dao, plugin_name, route_id, nil, consumer_id)
    ok, err = cache_set(cache, key, entity)
    if not ok then
      return nil, err
    end

    key = get_key(dao, plugin_name, nil, nil, consumer_id)
    ok, err = cache_add(cache, key, nil)
    if not ok then
      return nil, err
    end

    key = get_key(dao, plugin_name, route_id, nil, nil)
    ok, err = cache_add(cache, key, nil)
    if not ok then
      return nil, err
    end

    key = get_key(dao, plugin_name, nil, nil, nil)
    ok, err = cache_add(cache, key, nil)
    if not ok then
      return nil, err
    end

    return true
  end

  if service_id and consumer_id then
    key = get_key(dao, plugin_name, nil, service_id, consumer_id)
    ok, err = cache_set(cache, key, entity)
    if not ok then
      return nil, err
    end

    key = get_key(dao, plugin_name, nil, nil, consumer_id)
    ok, err = cache_add(cache, key, nil)
    if not ok then
      return nil, err
    end

    key = get_key(dao, plugin_name, nil, service_id, nil)
    ok, err = cache_add(cache, key, nil)
    if not ok then
      return nil, err
    end

    key = get_key(dao, plugin_name, nil, nil, nil)
    ok, err = cache_add(cache, key, nil)
    if not ok then
      return nil, err
    end

    return true
  end

  if route_id and service_id then
    key = get_key(dao, plugin_name, route_id, service_id, nil)
    ok, err = cache_set(cache, key, entity)
    if not ok then
      return nil, err
    end

    key = get_key(dao, plugin_name, route_id, nil, nil)
    ok, err = cache_add(cache, key, nil)
    if not ok then
      return nil, err
    end

    key = get_key(dao, plugin_name, nil, service_id, nil)
    ok, err = cache_add(cache, key, nil)
    if not ok then
      return nil, err
    end

    key = get_key(dao, plugin_name, nil, nil, nil)
    ok, err = cache_add(cache, key, nil)
    if not ok then
      return nil, err
    end

    return true
  end

  if consumer_id then
    key = get_key(dao, plugin_name, nil, nil, consumer_id)
    ok, err = cache_set(cache, key, entity)
    if not ok then
      return nil, err
    end

    key = get_key(dao, plugin_name, nil, nil, nil)
    ok, err = cache_add(cache, key, nil)
    if not ok then
      return nil, err
    end

    return true
  end

  if route_id then
    key = get_key(dao, plugin_name, route_id, nil, nil)
    ok, err = cache_set(cache, key, entity)
    if not ok then
      return nil, err
    end

    key = get_key(dao, plugin_name, nil, nil, nil)
    ok, err = cache_add(cache, key, nil)
    if not ok then
      return nil, err
    end

    return true
  end

  if service_id then
    key = get_key(dao, plugin_name, nil, service_id, nil)
    ok, err = cache_set(cache, key, entity)
    if not ok then
      return nil, err
    end

    key = get_key(dao, plugin_name, nil, nil, nil)
    ok, err = cache_add(cache, key, nil)
    if not ok then
      return nil, err
    end

    return true
  end

  -- if every other combination has failed, then it's a global plugin
  key = get_key(dao, plugin_name, nil, nil, nil)
  return cache_set(cache, key, entity)
end


local function cache_prewarm_single_entity(entity_name)
  local dao = kong.db[entity_name]
  if not dao then
    return nil, "Invalid entity name found when prewarming the cache: " .. tostring(entity_name)
  end

  ngx.log(ngx.NOTICE, "Preloading '" .. entity_name .. "' into the cache ...")

  local start = ngx.now()

  local ok
  for entity, err in dao:each(1000) do
    if err then
      return nil, err
    end

    ok, err = write_entity_in_cache(entity_name, dao, entity)
    if not ok then
      return nil, err
    end
  end

  local ellapsed = math.floor((ngx.now() - start) * 1000)

  ngx.log(ngx.NOTICE, "Finished preloading '" .. entity_name ..
                      "' into the cache. Ellapsed time: " .. tostring(ellapsed) .. "ms.")
  return true
end


-- Loads entities from the database into the cache, for rapid subsequent
-- access. This function is intented to be used during worker initialization
-- The list of entities to be loaded is defined by the ENTITIES_TO_PREWARM
-- variable.
function cache_prewarm.execute(configured_plugins)

  -- kong.db and kong.cache might not be active while running tests
  if not kong.db or not kong.cache then
    return true
  end

  for entity_name, dao in pairs(kong.db.daos) do
    if dao.schema.prewarm then
      local prewarm = CORE_ENTITIES[entity_name]
      if not prewarm and dao.plugin_name then
        prewarm = configured_plugins[dao.plugin_name]
      end

      if prewarm then
        local ok, err = cache_prewarm_single_entity(entity_name, dao)
        if not ok then
          if err == "no memory" then
            kong.log.warn("cache prewarming has been stopped because cache ",
                          "memory is exhausted, please consider increasing ",
                          "the value of 'mem_cache_size' (currently at ",
                          kong.configuration.mem_cache_size, ") for ",
                          "optimal performance")

            return true
          end

          return nil, err
        end
      end
    end
  end

  return true
end


return cache_prewarm
