-- TODO: get rid of 'kong.meta'; this module is king
local meta = require "kong.meta"
local PDK = require "kong.pdk"
local phase_checker = require "kong.pdk.private.phases"
local kong_cache = require "kong.cache"
local kong_cluster_events = require "kong.cluster_events"


local type = type
local setmetatable = setmetatable


local KONG_VERSION = tostring(meta._VERSION)
local KONG_VERSION_NUM = tonumber(string.format("%d%.2d%.2d",
                                  meta._VERSION_TABLE.major * 100,
                                  meta._VERSION_TABLE.minor * 10,
                                  meta._VERSION_TABLE.patch))


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

  if not self.ctx then
    error("ctx PDK module not initialized", 2)
  end

  self.ctx.keys[name] = key
end


function _GLOBAL.set_phase(self, phase)
  if not self then
    error("arg #1 cannot be nil", 2)
  end

  local kctx = self.ctx
  if not kctx then
    error("ctx SDK module not initialized", 2)
  end

  kctx.core.phase = phase
end


do
  local log_facilities = {
    core = nil,
    namespaced = setmetatable({}, { __index = "k" }),
  }


  function _GLOBAL.set_namespaced_log(self, namespace)
    if not self then
      error("arg #1 cannot be nil", 2)
    end

    if type(namespace) ~= "string" then
      error("namespace (arg #2) must be a string", 2)
    end

    local log = log_facilities.namespaced[namespace]
    if not log then
      log = self.log.new(namespace) -- use default namespaced format
      log_facilities.namespaced[namespace] = log
    end

    self.log = log
  end


  function _GLOBAL.reset_log(self)
    if not self then
      error("arg #1 cannot be nil", 2)
    end

    self.log = log_facilities.core
  end


  function _GLOBAL.init_pdk(self, kong_config, pdk_major_version)
    if not self then
      error("arg #1 cannot be nil", 2)
    end

    PDK.new(kong_config, pdk_major_version, self)

    log_facilities.core = self.log
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
      db                      = db,
      poll_interval           = kong_config.db_update_frequency,
      poll_offset             = kong_config.db_update_propagation,
    })
  end


  function _GLOBAL.init_cache(kong_config, cluster_events, worker_events)
    local db_cache_ttl = kong_config.db_cache_ttl
    local cache_pages = 1
    if kong_config.database == "off" then
      db_cache_ttl = 0
      cache_pages = 2
    end

    return kong_cache.new {
      shm_name          = "kong_db_cache",
      cluster_events    = cluster_events,
      worker_events     = worker_events,
      propagation_delay = kong_config.db_update_propagation,
      ttl               = db_cache_ttl,
      neg_ttl           = db_cache_ttl,
      resurrect_ttl     = kong_config.resurrect_ttl,
      cache_pages       = cache_pages,
      resty_lock_opts   = {
        exptime = 10,
        timeout = 5,
      },
    }
  end


  function _GLOBAL.init_core_cache(kong_config, cluster_events, worker_events)
    local db_cache_ttl = kong_config.db_cache_ttl
    local cache_pages = 1
    if kong_config.database == "off" then
      db_cache_ttl = 0
      cache_pages = 2
    end

    return kong_cache.new {
      shm_name          = "kong_core_db_cache",
      cluster_events    = cluster_events,
      worker_events     = worker_events,
      propagation_delay = kong_config.db_update_propagation,
      ttl               = db_cache_ttl,
      neg_ttl           = db_cache_ttl,
      resurrect_ttl     = kong_config.resurrect_ttl,
      cache_pages       = cache_pages,
      resty_lock_opts   = {
        exptime = 10,
        timeout = 5,
      },
    }
  end
end


return _GLOBAL
