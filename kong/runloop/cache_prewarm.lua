local kong = kong
local now = ngx.now
local floor = math.floor
local ipairs = ipairs
local tostring = tostring


local cache_prewarm = {}


local ENTITIES_TO_PREWARM = {
  "services",
  "plugins",
}


local function cache_prewarm_single_entity(entity_name)
  local dao = kong.db[entity_name]
  if not dao then
    return nil, "invalid entity name found when prewarming cache: " ..
                tostring(entity_name)
  end

  kong.log.notice("preloading '", entity_name, "' into cache")

  local start = now()

  for entity, err in dao:each(1000) do
    if err then
      return nil, err
    end

    local free_space = kong.cache:free_space()
    local cache_key  = dao:cache_key(entity)
    local ok, err    = kong.cache:get(cache_key, nil, function()
      return entity
    end)
    if not ok then
      return nil, err
    end

    if kong.cache:free_space() >= free_space then
      kong.log.warn("cache memory is exhausted, please consider raising the ",
                    "'mem_cache_size=", kong.configuration.mem_cache_size, "'")

      return nil
    end
  end

  local elapsed = floor((now() - start) * 1000)

  kong.log.notice("finished preloading '", entity_name,
                  "' into cache within ", tostring(elapsed), " ms")
  return true
end


-- Loads entities from the database into the cache, for rapid subsequent
-- access. This function is intented to be used during worker initialization
-- The list of entities to be loaded is defined by the ENTITIES_TO_PREWARM
-- variable.
function cache_prewarm.execute()
  -- kong.db and kong.cache might not be active while running tests
  if not kong.db or not kong.cache then
    return true
  end

  for _, entity_name in ipairs(ENTITIES_TO_PREWARM) do
    local ok, err = cache_prewarm_single_entity(entity_name)
    if not ok then
      if err then
        return nil, err
      else
        return true
      end
    end
  end

  return true
end


return cache_prewarm
