local cache_warmup = {}


local tostring = tostring
local pairs = pairs
local math = math
local kong = kong
local ngx = ngx


local ENTITIES_TO_WARMUP = {
  ["services"] = true,
  ["plugins"] = true,
}


local function fail_cb()
  error("this should never be called as L2 should already be warmed")
end


local function cache_warmup_single_entity(dao)
  local entity_name = dao.schema.name

  ngx.log(ngx.NOTICE, "Preloading '", entity_name, "' into the cache ...")

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

    -- NOTE: this is just for warming up L1
    ok, err = kong.cache:get(cache_key, nil, fail_cb)
    if not ok then
      return nil, err
    end
  end

  local elapsed = math.floor((ngx.now() - start) * 1000)

  ngx.log(ngx.NOTICE, "finished preloading '", entity_name,
                      "' into the cache (in ", tostring(elapsed), "ms)")
  return true
end


-- Loads entities from the database into the cache, for rapid subsequent
-- access. This function is intented to be used during worker initialization
-- The list of entities to be loaded is defined by the ENTITIES_TO_WARMUP
-- variable.
function cache_warmup.execute(configured_plugins)
  if not kong.cache then
    return true
  end

  for entity_name, dao in pairs(kong.db.daos) do
    local warmup = ENTITIES_TO_WARMUP[entity_name]
    if not warmup and dao.plugin_name then
      warmup = configured_plugins[dao.plugin_name]
    end

    if warmup then
      local ok, err = cache_warmup_single_entity(dao)
      if not ok then
        if err == "no memory" then
          kong.log.warn("cache warmup has been stopped because cache ",
                        "memory is exhausted, please consider increasing ",
                        "the value of 'mem_cache_size' (currently at ",
                        kong.configuration.mem_cache_size, ")")

          return true
        end
        return nil, err
      end
    end
  end

  return true
end


return cache_warmup
