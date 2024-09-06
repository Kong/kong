local hostname_type = require("kong.tools.ip").hostname_type
local constants = require "kong.constants"
local buffer = require "string.buffer"
local acl_groups


local load_module_if_exists = require "kong.tools.module".load_module_if_exists
if load_module_if_exists("kong.plugins.acl.groups") then
  acl_groups = require "kong.plugins.acl.groups"
end


local cache_warmup = {}


local encode = buffer.encode
local tostring = tostring
local ipairs = ipairs
local math = math
local max = math.max
local floor = math.floor
local kong = kong
local type = type
local ngx = ngx
local now = ngx.now
local log = ngx.log
local NOTICE  = ngx.NOTICE
local DEBUG = ngx.DEBUG

local NO_TTL_FLAG = require("kong.resty.mlcache").NO_TTL_FLAG


local GLOBAL_QUERY_OPTS = { workspace = ngx.null, show_ws_id = true }


function cache_warmup._mock_kong(mock_kong)
  kong = mock_kong
end


local function warmup_dns(premature, hosts, count)
  if premature then
    return
  end

  log(NOTICE, "warming up DNS entries ...")

  local start = now()

  local upstreams_dao = kong.db["upstreams"]
  local upstreams_names = {}
  if upstreams_dao then
    local page_size
    if upstreams_dao.pagination then
      page_size = upstreams_dao.pagination.max_page_size
    end

    for upstream, err in upstreams_dao:each(page_size, GLOBAL_QUERY_OPTS) do
      if err then
        log(NOTICE, "failed to iterate over upstreams: ", err)
        break
      end

      upstreams_names[upstream.name] = true
    end
  end

  for i = 1, count do
    local host = hosts[i]
    local must_warm_up = upstreams_names[host] == nil

    -- warmup DNS entry only if host is not an upstream name
    if must_warm_up then
      kong.dns.toip(host)
    end
  end

  local elapsed = floor((now() - start) * 1000)

  log(NOTICE, "finished warming up DNS entries",
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
    local value = encode(entity)
    ok, err =  ngx.shared.kong_core_db_cache:safe_set(cache_key, value, ttl, ttl == 0 and NO_TTL_FLAG or 0)
  end

  if not ok then
    return nil, err
  end

  return true
end


function cache_warmup.single_dao(dao)
  local entity_name = dao.schema.name
  local cache_store = constants.ENTITY_CACHE_STORE[entity_name]

  log(NOTICE, "Preloading '", entity_name, "' into the ", cache_store, "...")

  local start = now()

  local hosts_array, hosts_set, host_count
  if entity_name == "services" then
    hosts_array = {}
    hosts_set = {}
    host_count = 0
  end

  local page_size
  if dao.pagination then
    page_size = dao.pagination.max_page_size
  end
  for entity, err in dao:each(page_size, GLOBAL_QUERY_OPTS) do
    if err then
      return nil, err
    end

    if entity_name == "services" then
      if hostname_type(entity.host) == "name"
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

    if entity_name == "acls" and acl_groups ~= nil then
      log(DEBUG, "warmup acl groups cache for consumer id: ", entity.consumer.id , "...")
      local _, err = acl_groups.warmup_groups_cache(entity.consumer.id)
      if err then
        log(NOTICE, "warmup acl groups cache for consumer id: ", entity.consumer.id , " err: ", err)
      end
    end
  end

  if entity_name == "services" and host_count > 0 then
    ngx.timer.at(0, warmup_dns, hosts_array, host_count)
  end

  local elapsed = floor((now() - start) * 1000)

  log(NOTICE, "finished preloading '", entity_name,
                      "' into the ", cache_store, " (in ", tostring(elapsed), "ms)")
  return true
end


-- Loads entities from the database into the cache, for rapid subsequent
-- access. This function is intended to be used during worker initialization.
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
