local resty_mlcache = require "resty.mlcache"


local type    = type
local max     = math.max
local ngx_log = ngx.log
local ERR     = ngx.ERR
local NOTICE  = ngx.NOTICE
local DEBUG   = ngx.DEBUG


--[[
Hypothesis
----------

Item size:        1024 bytes
Max memory limit: 500 MiBs

LRU size must be: (500 * 2^20) / 1024 = 512000
Floored: 500.000 items should be a good default
--]]
local LRU_SIZE = 5e5


-------------------------------------------------------------------------------
-- NOTE: the following is copied from lua-resty-mlcache:                     --
------------------------------------------------------------------------ cut --
local cjson = require "cjson.safe"


local fmt = string.format
local now = ngx.now


local TYPES_LOOKUP = {
  number  = 1,
  boolean = 2,
  string  = 3,
  table   = 4,
}


local marshallers = {
  shm_value = function(str_value, value_type, at, ttl)
      return fmt("%d:%f:%f:%s", value_type, at, ttl, str_value)
  end,

  shm_nil = function(at, ttl)
      return fmt("0:%f:%f:", at, ttl)
  end,

  [1] = function(number) -- number
      return tostring(number)
  end,

  [2] = function(bool)   -- boolean
      return bool and "true" or "false"
  end,

  [3] = function(str)    -- string
      return str
  end,

  [4] = function(t)      -- table
      local json, err = cjson.encode(t)
      if not json then
          return nil, "could not encode table value: " .. err
      end

      return json
  end,
}


local function marshall_for_shm(value, ttl, neg_ttl)
  local at = now()

  if value == nil then
      return marshallers.shm_nil(at, neg_ttl), nil, true -- is_nil
  end

  -- serialize insertion time + Lua types for shm storage

  local value_type = TYPES_LOOKUP[type(value)]

  if not marshallers[value_type] then
      error("cannot cache value of type " .. type(value))
  end

  local str_marshalled, err = marshallers[value_type](value)
  if not str_marshalled then
      return nil, "could not serialize value for lua_shared_dict insertion: "
                  .. err
  end

  return marshallers.shm_value(str_marshalled, value_type, at, ttl)
end
------------------------------------------------------------------------ end --


local _init = {}


local function log(lvl, ...)
  return ngx_log(lvl, "[DB cache] ", ...)
end


local _M = {}
local mt = { __index = _M }


function _M.new(opts)
  if type(opts.shm_name) ~= "string" then
    error("opts.shm_name must be a string", 2)
  end

  if _init[opts.shm_name] then
    error("kong.cache (" .. opts.shm_name .. ") was already created", 2)
  end

  -- opts validation

  opts = opts or {}

  if not opts.cluster_events then
    error("opts.cluster_events is required", 2)
  end

  if not opts.worker_events then
    error("opts.worker_events is required", 2)
  end

  if opts.ttl and type(opts.ttl) ~= "number" then
    error("opts.ttl must be a number", 2)
  end

  if opts.neg_ttl and type(opts.neg_ttl) ~= "number" then
    error("opts.neg_ttl must be a number", 2)
  end

  if opts.cache_pages and opts.cache_pages ~= 1 and opts.cache_pages ~= 2 then
    error("opts.cache_pages must be 1 or 2", 2)
  end

  if opts.resty_lock_opts and type(opts.resty_lock_opts) ~= "table" then
    error("opts.resty_lock_opts must be a table", 2)
  end

  local mlcaches = {}
  local shm_names = {}

  for i = 1, opts.cache_pages or 1 do
    local channel_name  = (i == 1) and "mlcache"                 or "mlcache_2"
    local shm_name      = (i == 1) and opts.shm_name             or opts.shm_name .. "_2"
    local shm_miss_name = (i == 1) and opts.shm_name .. "_miss"  or opts.shm_name .. "_miss_2"

    if not ngx.shared[shm_name] then
      log(ERR, "shared dictionary ", shm_name, " not found")
    end

    if not ngx.shared[shm_miss_name] then
      log(ERR, "shared dictionary ", shm_miss_name, " not found")
    end

    if ngx.shared[shm_name] then
      local mlcache, err = resty_mlcache.new(shm_name, shm_name, {
        shm_miss         = shm_miss_name,
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
              end, channel_name, event_t.channel)
            end
          end,
          broadcast = function(channel, data)
            local ok, err = opts.worker_events.post(channel_name, channel, data)
            if not ok then
              log(ERR, "failed to post event '", channel_name, "', '",
                       channel, "': ", err)
            end
          end
        }
      })
      if not mlcache then
        return nil, "failed to instantiate mlcache: " .. err
      end
      mlcaches[i] = mlcache
      shm_names[i] = shm_name
    end
  end

  local curr_mlcache = 1

  if opts.cache_pages == 2 then
    curr_mlcache = ngx.shared.kong:get("kong:cache:" .. opts.shm_name .. ":curr_mlcache") or 1
  end

  local self          = {
    cluster_events    = opts.cluster_events,
    mlcache           = mlcaches[curr_mlcache],
    mlcaches          = mlcaches,
    shm_names         = shm_names,
    curr_mlcache      = curr_mlcache,
  }

  local ok, err = self.cluster_events:subscribe("invalidations", function(key)
    log(DEBUG, "received invalidate event from cluster for key: '", key, "'")
    self:invalidate_local(key)
  end)
  if not ok then
    return nil, "failed to subscribe to invalidations cluster events " ..
                "channel: " .. err
  end

  _init[opts.shm_name] = true

  return setmetatable(self, mt)
end


function _M:save_curr_page()
  return ngx.shared.kong:set(
    "kong:cache:" .. self.shm_names[1] .. ":curr_mlcache", self.curr_mlcache)
end


function _M:get(key, opts, cb, ...)
  if type(key) ~= "string" then
    error("key must be a string", 2)
  end

  local shadow = (opts or {}).shadow

  local current_page = self.curr_mlcache or 1
  local get_page
  if shadow and #self.mlcaches == 2 then
    get_page = current_page == 1 and 2 or 1
  else
    get_page = current_page
  end

  local v, err = self.mlcaches[get_page]:get(key, opts, cb, ...)
  if err then
    return nil, "failed to get from node cache: " .. err
  end

  return v
end


function _M:get_bulk(bulk, opts)
  if type(bulk) ~= "table" then
    error("bulk must be a table", 2)
  end

  if opts ~= nil and type(opts) ~= "table" then
    error("opts must be a table", 2)
  end

  local shadow = (opts or {}).shadow

  local current_page = self.curr_mlcache or 1
  local get_bulk_page
  if shadow and #self.mlcaches == 2 then
    get_bulk_page = current_page == 1 and 2 or 1
  else
    get_bulk_page = current_page
  end

  local res, err = self.mlcaches[get_bulk_page]:get_bulk(bulk, opts)
  if err then
    return nil, "failed to get_bulk from node cache: " .. err
  end

  return res
end


function _M:safe_set(key, value, shadow)
  local str_marshalled, err = marshall_for_shm(value, self.mlcache.ttl,
                                                      self.mlcache.neg_ttl)
  if err then
    return nil, err
  end

  local current_page = self.curr_mlcache or 1

  local set_page
  if shadow and #self.mlcaches == 2 then
    set_page = current_page == 1 and 2 or 1
  else
    set_page = current_page
  end

  local shm_name = self.shm_names[set_page]
  return ngx.shared[shm_name]:safe_set(shm_name .. key, str_marshalled)
end


function _M:probe(key, shadow)
  if type(key) ~= "string" then
    error("key must be a string", 2)
  end

  local current_page = self.curr_mlcache or 1
  local probe_page
  if shadow and #self.mlcaches == 2 then
    probe_page = current_page == 1 and 2 or 1
  else
    probe_page = current_page
  end

  local ttl, err, v = self.mlcaches[probe_page]:peek(key)
  if err then
    return nil, "failed to probe from node cache: " .. err
  end

  return ttl, nil, v
end


function _M:invalidate_local(key, shadow)
  if type(key) ~= "string" then
    error("key must be a string", 2)
  end

  log(DEBUG, "invalidating (local): '", key, "'")

  local current_page = self.curr_mlcache or 1
  local delete_page
  if shadow and #self.mlcaches == 2 then
    delete_page = current_page == 1 and 2 or 1
  else
    delete_page = current_page
  end

  local ok, err = self.mlcaches[delete_page]:delete(key)
  if not ok then
    log(ERR, "failed to delete entity from node cache: ", err)
  end
end


function _M:invalidate(key, shadow)
  if type(key) ~= "string" then
    error("key must be a string", 2)
  end

  self:invalidate_local(key, shadow)

  if shadow then
    return
  end

  log(DEBUG, "broadcasting (cluster) invalidation for key: '", key, "'")

  local ok, err = self.cluster_events:broadcast("invalidations", key)
  if not ok then
    log(ERR, "failed to broadcast cached entity invalidation: ", err)
  end
end


function _M:purge(shadow)
  log(NOTICE, "purging (local) cache")

  local current_page = self.curr_mlcache or 1
  local purge_page
  if shadow and #self.mlcaches == 2 then
    purge_page = current_page == 1 and 2 or 1
  else
    purge_page = current_page
  end

  local ok, err = self.mlcaches[purge_page]:purge(true)
  if not ok then
    log(ERR, "failed to purge cache: ", err)
  end
end


function _M:flip()
  if #self.mlcaches == 1 then
    return
  end

  log(DEBUG, "flipping current cache")

  local current_page = self.curr_mlcache or 1
  local next_page = current_page == 1 and 2 or 1

  self.curr_mlcache = next_page
  self.mlcache = self.mlcaches[next_page]
end


return _M
