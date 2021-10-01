-- TODO: get rid of 'kong.meta'; this module is king
local meta = require "kong.meta"
local PDK = require "kong.pdk"
local phase_checker = require "kong.pdk.private.phases"
local kong_cache = require "kong.cache"
local kong_cluster_events = require "kong.cluster_events"
local kong_constants = require "kong.constants"

local ngx = ngx
local type = type
local error = error
local setmetatable = setmetatable


local KONG_VERSION = tostring(meta._VERSION)
local KONG_VERSION_NUM = tonumber(string.format("%d%.2d%.2d",
                                  meta._VERSION_TABLE.major * 100,
                                  meta._VERSION_TABLE.minor * 10,
                                  meta._VERSION_TABLE.patch))


local LOCK_OPTS = {
  exptime = 10,
  timeout = 5,
}


-- Runloop interface


local _GLOBAL = {
  phases = phase_checker.phases,
}


function _GLOBAL.new()
  return {
    version = KONG_VERSION,
    version_num = KONG_VERSION_NUM,

    pdk_major_version = nil,
    pdk_version = nil,

    configuration = nil,
  }
end


function _GLOBAL.set_named_ctx(self, name, key)
  if not self then
    error("arg #1 cannot be nil", 2)
  end

  if type(name) ~= "string" then
    error("name must be a string", 2)
  end

  if #name == 0 then
    error("name cannot be an empty string", 2)
  end

  if key == nil then
    error("key cannot be nil", 2)
  end

  if not self.ctx then
    error("ctx PDK module not initialized", 2)
  end

  self.ctx.__set_namespace(name, key)
end


function _GLOBAL.del_named_ctx(self, name)
  if not self then
    error("arg #1 cannot be nil", 2)
  end

  if type(name) ~= "string" then
    error("name must be a string", 2)
  end

  if #name == 0 then
    error("name cannot be an empty string", 2)
  end

  if not self.ctx then
    error("ctx PDK module not initialized", 2)
  end

  self.ctx.__del_namespace(name)
end


do
  local log_facilities = setmetatable({}, { __index = "k" })


  function _GLOBAL.set_namespaced_log(self, namespace, ctx)
    if not self then
      error("arg #1 cannot be nil", 2)
    end

    if type(namespace) ~= "string" then
      error("namespace (arg #2) must be a string", 2)
    end

    local log = log_facilities[namespace]
    if not log then
      log = self._log.new(namespace) -- use default namespaced format
      log_facilities[namespace] = log
    end

    (ctx or ngx.ctx).KONG_LOG = log
  end


  function _GLOBAL.reset_log(self, ctx)
    if not self then
      error("arg #1 cannot be nil", 2)
    end

    (ctx or ngx.ctx).KONG_LOG = self._log
  end
end


function _GLOBAL.init_pdk(self, kong_config, pdk_major_version)
  if not self then
    error("arg #1 cannot be nil", 2)
  end

  PDK.new(kong_config, pdk_major_version, self)
end


function _GLOBAL.init_worker_events()
  -- Note: worker_events will not work correctly if required at the top of the file.
  --       It must be required right here, inside the init function
  local worker_events = require "resty.worker.events"

  local ok, err = worker_events.configure {
    shm = "kong_process_events", -- defined by "lua_shared_dict"
    timeout = 5,            -- life time of event data in shm
    interval = 1,           -- poll interval (seconds)

    wait_interval = 0.010,  -- wait before retry fetching event data
    wait_max = 0.5,         -- max wait time before discarding event
  }
  if not ok then
    return nil, err
  end

  return worker_events
end


function _GLOBAL.init_cluster_events(kong_config, db)
  return kong_cluster_events.new({
    db            = db,
    poll_interval = kong_config.db_update_frequency,
    poll_offset   = kong_config.db_update_propagation,
    poll_delay    = kong_config.db_update_propagation,
  })
end


function _GLOBAL.init_cache(kong_config, cluster_events, worker_events)
  local db_cache_ttl = kong_config.db_cache_ttl
  local db_cache_neg_ttl = kong_config.db_cache_neg_ttl
  local page = 1
  local cache_pages = 1

  if kong_config.database == "off" then
    db_cache_ttl = 0
    db_cache_neg_ttl = 0
    cache_pages = 2
    page = ngx.shared.kong:get(kong_constants.DECLARATIVE_PAGE_KEY) or page
  end

  return kong_cache.new {
    shm_name        = "kong_db_cache",
    cluster_events  = cluster_events,
    worker_events   = worker_events,
    ttl             = db_cache_ttl,
    neg_ttl         = db_cache_neg_ttl or db_cache_ttl,
    resurrect_ttl   = kong_config.resurrect_ttl,
    page            = page,
    cache_pages     = cache_pages,
    resty_lock_opts = LOCK_OPTS,
  }
end


function _GLOBAL.init_core_cache(kong_config, cluster_events, worker_events)
  local db_cache_ttl = kong_config.db_cache_ttl
  local db_cache_neg_ttl = kong_config.db_cache_neg_ttl
  local page = 1
  local cache_pages = 1
  if kong_config.database == "off" then
    db_cache_ttl = 0
    db_cache_neg_ttl = 0
    cache_pages = 2
    page = ngx.shared.kong:get(kong_constants.DECLARATIVE_PAGE_KEY) or page
  end

  return kong_cache.new {
    shm_name        = "kong_core_db_cache",
    cluster_events  = cluster_events,
    worker_events   = worker_events,
    ttl             = db_cache_ttl,
    neg_ttl         = db_cache_neg_ttl or db_cache_ttl,
    resurrect_ttl   = kong_config.resurrect_ttl,
    page            = page,
    cache_pages     = cache_pages,
    resty_lock_opts = LOCK_OPTS,
  }
end


return _GLOBAL
