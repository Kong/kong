local resty_mlcache    = require "resty.mlcache"


local type             = type
local fmt              = string.format
local math             = math
local error            = error
local pairs            = pairs
local ngx_log          = ngx.log
local ngx_now          = ngx.now
local ngx_shared       = ngx.shared
local worker_id        = ngx.worker.id
local timer_every      = ngx.timer.every
local setmetatable     = setmetatable


local ERR              = ngx.ERR
local WARN             = ngx.WARN
local NOTICE           = ngx.NOTICE
local INFO             = ngx.INFO
local DEBUG            = ngx.DEBUG


local SHM_LOCKS        = "kong_locks"
local SHM_CACHE        = "kong_db_cache"
local SHM_CACHE_MISSES = "kong_db_cache_miss"


--[[
Hypothesis
----------

Item size:        1024 bytes
Max memory limit: 500 MiBs

LRU size must be: (500 * 2^20) / 1024 = 512000
Floored: 500.000 items should be a good default
--]]
local LRU_SIZE = 5e5


local _init


local function log(lvl, ...)
  return ngx_log(lvl, "[DB cache] ", ...)
end


local function format_bytes(bytes, si)
  local unit = si and 1000 or 1024

  if bytes < unit then
    return bytes .. " B"
  end

  local exp = math.floor(math.log(bytes) / math.log(unit))

  local units = si and { "k",  "M",  "G",  "T",  "P",  "E"  } or
                       { "Ki", "Mi", "Gi", "Ti", "Pi", "Ei" }


  return fmt("%.1f %sB", bytes / (unit ^ exp), units[exp])
end


local function monitor(premature, cache)
  if premature then
    return
  end

  local size = cache.size
  local used = cache:used_space()

  local pct = used / size * 100

  local msg = fmt("%.1f%% of cache is used (%s / %s)", pct,
                  format_bytes(used, true), format_bytes(size, true))

  if pct >= 60 and pct < 80 then
    log(DEBUG, msg)
  elseif pct >= 80 and pct < 90 then
    log(INFO, msg)
  elseif pct >= 90 and pct < 95  then
    log(NOTICE, msg, ", please consider raising 'mem_cache_size'")
  elseif pct >= 95 then
    log(WARN, msg, ", please consider raising 'mem_cache_size'")
  end
end


local _M = {}
local mt = { __index = _M }


function _M.new(opts)
  if _init then
    return error("kong.cache was already created")
  end

  -- opts validation

  opts = opts or {}

  if not opts.cluster_events then
    return error("opts.cluster_events is required")
  end

  if not opts.worker_events then
    return error("opts.worker_events is required")
  end

  if opts.propagation_delay and type(opts.propagation_delay) ~= "number" then
    return error("opts.propagation_delay must be a number")
  end

  if opts.ttl and type(opts.ttl) ~= "number" then
    return error("opts.ttl must be a number")
  end

  if opts.neg_ttl and type(opts.neg_ttl) ~= "number" then
    return error("opts.neg_ttl must be a number")
  end

  if opts.resty_lock_opts and type(opts.resty_lock_opts) ~= "table" then
    return error("opts.resty_lock_opts must be a table")
  end

  local mlcache, err = resty_mlcache.new(SHM_CACHE, SHM_CACHE, {
    shm_miss         = SHM_CACHE_MISSES,
    shm_locks        = SHM_LOCKS,
    shm_set_retries  = 3,
    lru_size         = LRU_SIZE,
    ttl              = math.max(opts.ttl     or 3600, 0),
    neg_ttl          = math.max(opts.neg_ttl or 300,  0),
    resurrect_ttl    = opts.resurrect_ttl or 30,
    resty_lock_opts  = opts.resty_lock_opts,
    ipc = {
      register_listeners = function(events)
        for _, event_t in pairs(events) do
          opts.worker_events.register(function(data)
            event_t.handler(data)
          end, "mlcache", event_t.channel)
        end
      end,
      broadcast = function(channel, data)
        opts.worker_events.post("mlcache", channel, data)
      end
    }
  })
  if not mlcache then
    return nil, "failed to instantiate mlcache: " .. err
  end

  local self          = {
    propagation_delay = math.max(opts.propagation_delay or 0, 0),
    cluster_events    = opts.cluster_events,
    mlcache           = mlcache,
    size              = ngx_shared[SHM_CACHE]:capacity(),
  }

  local ok, err = self.cluster_events:subscribe("invalidations", function(key)
    log(DEBUG, "received invalidate event from cluster for key: '", key, "'")
    self:invalidate_local(key)
  end)
  if not ok then
    return nil, "failed to subscribe to invalidations cluster events " ..
                "channel: " .. err
  end

  if worker_id() == 0 then
    timer_every(60, monitor, self)
  end

  _init = true

  return setmetatable(self, mt)
end


function _M:get(key, opts, cb, ...)
  if type(key) ~= "string" then
    return error("key must be a string")
  end

  --log(DEBUG, "get from key: ", key)

  local v, err = self.mlcache:get(key, opts, cb, ...)
  if err then
    return nil, "failed to get from node cache: " .. err
  end

  return v
end


function _M:probe(key)
  if type(key) ~= "string" then
    return error("key must be a string")
  end

  local ttl, err, v = self.mlcache:peek(key)
  if err then
    return nil, "failed to probe from node cache: " .. err
  end

  return ttl, nil, v
end


function _M:invalidate_local(key)
  if type(key) ~= "string" then
    return error("key must be a string")
  end

  log(DEBUG, "invalidating (local): '", key, "'")

  local ok, err = self.mlcache:delete(key)
  if not ok then
    log(ERR, "failed to delete entity from node cache: ", err)
  end
end


function _M:invalidate(key)
  if type(key) ~= "string" then
    return error("key must be a string")
  end

  self:invalidate_local(key)

  local nbf
  if self.propagation_delay > 0 then
    nbf = ngx_now() + self.propagation_delay
  end

  log(DEBUG, "broadcasting (cluster) invalidation for key: '", key, "' ",
             "with nbf: '", nbf or "none", "'")

  local ok, err = self.cluster_events:broadcast("invalidations", key, nbf)
  if not ok then
    log(ERR, "failed to broadcast cached entity invalidation: ", err)
  end
end


function _M:purge()
  log(NOTICE, "purging (local) cache")

  local ok, err = self.mlcache:purge()
  if not ok then
    log(ERR, "failed to purge cache: ", err)
  end
end


function _M:used_space()
  return self.size - ngx_shared[SHM_CACHE]:free_space()
end


function _M:free_space()
  return ngx_shared[SHM_CACHE]:free_space()
end


return _M
