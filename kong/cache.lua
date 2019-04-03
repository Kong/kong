local resty_mlcache = require "resty.mlcache"
local reports = require "kong.reports"


local kong    = kong
local type    = type
local max     = math.max
local ngx_log = ngx.log
local ngx_now = ngx.now
local ERR     = ngx.ERR
local NOTICE  = ngx.NOTICE
local DEBUG   = ngx.DEBUG


local SHM_CACHE = "kong_db_cache"
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
    shm_miss         = "kong_db_cache_miss",
    shm_locks        = "kong_locks",
    shm_set_retries  = 3,
    lru_size         = LRU_SIZE,
    ttl              = max(opts.ttl     or 3600, 0),
    neg_ttl          = max(opts.neg_ttl or 300,  0),
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
    propagation_delay = max(opts.propagation_delay or 0, 0),
    cluster_events    = opts.cluster_events,
    mlcache           = mlcache,
    vitals            = kong.vitals,
  }

  local ok, err = self.cluster_events:subscribe("invalidations", function(key)
    log(DEBUG, "received invalidate event from cluster for key: '", key, "'")
    self:invalidate_local(key)
  end)
  if not ok then
    return nil, "failed to subscribe to invalidations cluster events " ..
                "channel: " .. err
  end

  _init = true

  return setmetatable(self, mt)
end


function _M:get(key, opts, cb, ...)
  if type(key) ~= "string" then
    return error("key must be a string")
  end

  --log(DEBUG, "get from key: ", key)

  local v, err, hit_lvl = self.mlcache:get(key, opts, cb, ...)
  if err then
    return nil, "failed to get from node cache: " .. err
  end

  kong.vitals:cache_accessed(hit_lvl, key, v)
  reports.report_cached_entity(v)

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


function _M:invalidate(key, workspaces)
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

  workspaces = workspaces or {}
  for _, ws in ipairs(workspaces) do

    local key_ws = key .. ws.id
    self:invalidate_local(key_ws)

    log(DEBUG, "broadcasting (cluster) invalidation for key: '", key_ws, "' ",
               "with nbf: '", nbf or "none", "'")

    local ok, err = self.cluster_events:broadcast("invalidations", key_ws, nbf)
    if not ok then
      log(ERR, "failed to broadcast cached entity invalidation: ", err)
    end
  end
end


function _M:purge()
  log(NOTICE, "purging (local) cache")

  local ok, err = self.mlcache:purge()
  if not ok then
    log(ERR, "failed to purge cache: ", err)
  end
end


return _M
