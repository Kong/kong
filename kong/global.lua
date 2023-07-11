-- TODO: get rid of 'kong.meta'; this module is king
local meta = require "kong.meta"
local PDK = require "kong.pdk"
local process = require "ngx.process"
local phase_checker = require "kong.pdk.private.phases"
local kong_cache = require "kong.cache"
local kong_cluster_events = require "kong.cluster_events"
local private_node = require "kong.pdk.private.node"

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


local _ns_mt = { __mode = "v" }
local function get_namespaces(self, ctx)
  if not ctx then
    ctx = ngx.ctx
  end

  local namespaces = ctx.KONG_NAMESPACES
  if not namespaces then
    -- 4 namespaces for request, i.e. ~4 plugins
    namespaces = self.table.new(0, 4)
    ctx.KONG_NAMESPACES = setmetatable(namespaces, _ns_mt)
  end

  return namespaces
end


local function set_namespace(self, namespace, namespace_key, ctx)
  local namespaces = get_namespaces(self, ctx)

  local ns = namespaces[namespace]
  if ns and ns == namespace_key then
    return
  end

  namespaces[namespace] = namespace_key
end


local function del_namespace(self, namespace, ctx)
  if not ctx then
    ctx = ngx.ctx
  end

  local namespaces = get_namespaces(self, ctx)
  namespaces[namespace] = nil
end


-- Runloop interface


local _GLOBAL = {
  phases = phase_checker.phases,
}


function _GLOBAL.new()
  return {
    version = KONG_VERSION,
    version_num = KONG_VERSION_NUM,

    configuration = nil,
  }
end


function _GLOBAL.set_named_ctx(self, name, key, ctx)
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

  if not self.table then
    error("ctx PDK module not initialized", 2)
  end

  set_namespace(self, name, key, ctx)
end


function _GLOBAL.del_named_ctx(self, name, ctx)
  if not self then
    error("arg #1 cannot be nil", 2)
  end

  if type(name) ~= "string" then
    error("name must be a string", 2)
  end

  if #name == 0 then
    error("name cannot be an empty string", 2)
  end

  del_namespace(self, name, ctx)
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


function _GLOBAL.init_pdk(self, kong_config)
  if not self then
    error("arg #1 cannot be nil", 2)
  end

  private_node.init_node_id(kong_config)

  PDK.new(kong_config, self)
end


function _GLOBAL.init_worker_events()
  -- Note: worker_events will not work correctly if required at the top of the file.
  --       It must be required right here, inside the init function
  local worker_events
  local opts

  local configuration = kong.configuration

  -- `kong.configuration.prefix` is already normalized to an absolute path,
  -- but `ngx.config.prefix()` is not
  local prefix = configuration
                 and configuration.prefix
                 or require("pl.path").abspath(ngx.config.prefix())

  local sock = ngx.config.subsystem == "stream"
               and "stream_worker_events.sock"
               or "worker_events.sock"

  local listening = "unix:" .. prefix .. "/" .. sock

  opts = {
    unique_timeout = 5,     -- life time of unique event data in lrucache
    broker_id = 0,          -- broker server runs in nginx worker #0
    listening = listening,  -- unix socket for broker listening
    max_queue_len = 1024 * 50,  -- max queue len for events buffering
  }

  worker_events = require "resty.events.compat"

  local ok, err = worker_events.configure(opts)
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


local function get_lru_size(kong_config)
  if (process.type() == "privileged agent")
  or (kong_config.role == "control_plane")
  or (kong_config.role == "traditional" and #kong_config.proxy_listeners  == 0
                                        and #kong_config.stream_listeners == 0)
  then
    return 1000
  end
end


function _GLOBAL.init_cache(kong_config, cluster_events, worker_events)
  local db_cache_ttl = kong_config.db_cache_ttl
  local db_cache_neg_ttl = kong_config.db_cache_neg_ttl
  local page = 1
  local cache_pages = 1

  if kong_config.database == "off" then
    db_cache_ttl = 0
    db_cache_neg_ttl = 0
   end

  return kong_cache.new({
    shm_name        = "kong_db_cache",
    cluster_events  = cluster_events,
    worker_events   = worker_events,
    ttl             = db_cache_ttl,
    neg_ttl         = db_cache_neg_ttl or db_cache_ttl,
    resurrect_ttl   = kong_config.resurrect_ttl,
    page            = page,
    cache_pages     = cache_pages,
    resty_lock_opts = LOCK_OPTS,
    lru_size        = get_lru_size(kong_config),
  })
end


function _GLOBAL.init_core_cache(kong_config, cluster_events, worker_events)
  local db_cache_ttl = kong_config.db_cache_ttl
  local db_cache_neg_ttl = kong_config.db_cache_neg_ttl
  local page = 1
  local cache_pages = 1

  if kong_config.database == "off" then
    db_cache_ttl = 0
    db_cache_neg_ttl = 0
  end

  return kong_cache.new({
    shm_name        = "kong_core_db_cache",
    cluster_events  = cluster_events,
    worker_events   = worker_events,
    ttl             = db_cache_ttl,
    neg_ttl         = db_cache_neg_ttl or db_cache_ttl,
    resurrect_ttl   = kong_config.resurrect_ttl,
    page            = page,
    cache_pages     = cache_pages,
    resty_lock_opts = LOCK_OPTS,
    lru_size        = get_lru_size(kong_config),
  })
end


return _GLOBAL
