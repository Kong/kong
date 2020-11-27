local utils = require "kong.tools.utils"
local constants = require "kong.constants"
local marshall = require "kong.cache.marshall"


local cache_warmup = {}


local tostring = tostring
local ipairs = ipairs
local math = math
local max = math.max
local floor = math.floor
local kong = kong
local type = type
local ngx = ngx
local null = ngx.null



local GLOBAL_QUERY_OPTS = { workspace = null, show_ws_id = true }


function cache_warmup._mock_kong(mock_kong)
  kong = mock_kong
end


local function warmup_dns(premature, hosts, count)
  if premature then
    return
  end

  ngx.log(ngx.NOTICE, "warming up DNS entries ...")

  local start = ngx.now()

  for i = 1, count do
    kong.dns.toip(hosts[i])
  end

  local elapsed = floor((ngx.now() - start) * 1000)

  ngx.log(ngx.NOTICE, "finished warming up DNS entries",
                      "' into the cache (in ", tostring(elapsed), "ms)")
end


function cache_warmup.single_entity(dao, entity)
  local entity_name = dao.schema.name
  local cache_store = constants.ENTITY_CACHE_STORE[entity_name]
  local cache_key = dao:cache_key(entity)
  local cache = kong[cache_store]
  local ok, err
  if cache then
    ok, err = cache:safe_set(cache_key, entity)

  else
    cache_key = "kong_core_db_cache" .. cache_key
    local ttl = max(kong.configuration.db_cache_ttl or 3600, 0)
    local neg_ttl = max(kong.configuration.db_cache_neg_ttl or 300, 0)
    local value = marshall(entity, ttl, neg_ttl)
    ok, err =  ngx.shared.kong_core_db_cache:safe_set(cache_key, value)
  end

  if not ok then
    return nil, err
  end

  return true
end


function cache_warmup.single_dao(dao)
  local entity_name = dao.schema.name
  local cache_store = constants.ENTITY_CACHE_STORE[entity_name]

  ngx.log(ngx.NOTICE, "Preloading '", entity_name, "' into the ", cache_store, "...")

  local start = ngx.now()

  local hosts_array, hosts_set, host_count
  if entity_name == "services" then
    hosts_array = {}
    hosts_set = {}
    host_count = 0
  end

  for entity, err in dao:each(nil, GLOBAL_QUERY_OPTS) do
    if err then
      return nil, err
    end

    if entity_name == "services" then
      if utils.hostname_type(entity.host) == "name"
         and hosts_set[entity.host] == nil then
        host_count = host_count + 1
        hosts_array[host_count] = entity.host
        hosts_set[entity.host] = true
      end
    end

    local ok, err = cache_warmup.single_entity(dao, entity)
    if not ok then
      return nil, err
    end
  end

  if entity_name == "services" and host_count > 0 then
    ngx.timer.at(0, warmup_dns, hosts_array, host_count)
  end

  local elapsed = floor((ngx.now() - start) * 1000)

  ngx.log(ngx.NOTICE, "finished preloading '", entity_name,
                      "' into the ", cache_store, " (in ", tostring(elapsed), "ms)")
  return true
end


-- Loads entities from the database into the cache, for rapid subsequent
-- access. This function is intented to be used during worker initialization.
function cache_warmup.execute(entities)
  if not kong.cache or not kong.core_cache then
    return true
  end

  for _, entity_name in ipairs(entities) do
    if entity_name == "routes" then
      -- do not spend shm memory by caching individual Routes entries
      -- because the routes are kept in-memory by building the router object
      kong.log.notice("the 'routes' entity is ignored in the list of ",
                      "'db_cache_warmup_entities' because Kong ",
                      "caches routes in memory separately")
      goto continue
    end

    if entity_name == "plugins" then
      -- to speed up the init, the plugins are warmed up upon initial
      -- plugin iterator build
      kong.log.notice("the 'plugins' entity is ignored in the list of ",
                      "'db_cache_warmup_entities' because Kong ",
                      "pre-warms plugins automatically")
      goto continue
    end

    local dao = kong.db[entity_name]
    if not (type(dao) == "table" and dao.schema) then
      kong.log.warn(entity_name, " is not a valid entity name, please check ",
                    "the value of 'db_cache_warmup_entities'")
      goto continue
    end

    local ok, err = cache_warmup.single_dao(dao)
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

    ::continue::
  end

  return true
end


return cache_warmup
