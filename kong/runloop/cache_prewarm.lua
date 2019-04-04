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


local function cache_prewarm_single_entity(entity_name, dao)
  ngx.log(ngx.NOTICE, "Preloading '" .. entity_name .. "' into the cache ...")

  local start = ngx.now()

  for entity, err in dao:each(1000) do
    if err then
      return nil, err
    end

    local cache_key = dao:cache_key(entity)

    local ok, err = kong.cache:safe_set(cache_key, entity)
    if not ok then
      return nil, err
    end

    local ok, err   = kong.cache:get(cache_key, nil, function()
      return entity
    end)
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
                          kong.configuration.mem_cache_size, ")")

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
