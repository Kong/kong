-- TODO: get rid of 'kong.meta'; this module is king
local meta = require "kong.meta"
local PDK = require "kong.pdk"
local phase_checker = require "kong.pdk.private.phases"
local kong_cache = require "kong.cache"
local kong_cluster_events = require "kong.cluster_events"
local private_node = require "kong.pdk.private.node"

local cjson = require "cjson"
local string_buffer = require "string.buffer"
local uuid = require("kong.tools.utils").uuid

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

  local PAYLOAD_MAX_LEN, PAYLOAD_TOO_BIG_ERR = 65000, "failed to publish event: payload too big"

  -- There is a limit for the payload size that events lib allows to send,
  -- we overwrite `post` and `register` method to support sending large payloads
  local native_post = worker_events.post
  local function large_payload_post(source, event, data, unique)
    local serialized = 0
    if type(data) == "table" then
      data = cjson.encode(data)
      serialized = 1
    end

    local len_data = #data
    local len_sent = len_data
    local pt = 1
    local eid = uuid()
    while len_sent > 0 do
      local partial
      local packet = {}
      if len_sent <= PAYLOAD_MAX_LEN then
        partial = data:sub(pt, pt + len_sent - 1)
        packet["uuid"] = eid
        packet["length"] = len_data
        packet["serialized"] = serialized
      else
        partial = data:sub(pt, pt + PAYLOAD_MAX_LEN - 1)
      end

      packet["uuid"] = eid
      packet["data"] = partial
      packet["partial"] = 1
      ngx.log(ngx.ERR, "gonna send partial")
      local ok, err = native_post(source, event, packet, unique)
      if not ok then
        ngx.log(ngx.ERR, "error to send via native_post: ", err)
        -- explicitly reset the event buffer
        native_post(source, event, { uuid = eid, reset = 1 }, unique)
        return ok, err
      end

      pt = pt + PAYLOAD_MAX_LEN
      len_sent = len_sent - PAYLOAD_MAX_LEN
    end

    return true
  end

  worker_events.post = function(source, event, data, unique)
    local ok, err = native_post(source, event, data, unique)
    if err == PAYLOAD_TOO_BIG_ERR then
      return large_payload_post(source, event, data, unique)
    end

    return ok, err
  end

  local TTL = 10 * 60 -- 10 minutes
  local native_register = worker_events.register
  worker_events.register = function(callback, source, event, ...)
    local buffer_dict = {}

    local function recycle_buffer()
      ngx.log(ngx.DEBUG, "recycle buffer")
      if ngx.worker.exiting() then
        return
      end

      for eid, buffer in pairs(buffer_dict) do
        if ngx.now() - buffer.ts > TTL then
          buffer.buffer:reset()
          buffer_dict[eid] = nil
          ngx.log(ngx.DEBUG, eid, " in event buffer is recycled")
        end
      end

      ngx.timer.at(TTL, recycle_buffer)
    end

    ngx.timer.at(TTL, recycle_buffer)

    local function cb(data, ...)
      if data.partial == nil then
        return callback(data, ...)
      end

      local buffer = buffer_dict[data.uuid]
      local buf = buffer ~= nil and buffer.buffer
      if data.reset then
        if buffer ~= nil then
          buffer.buffer:reset()
          buffer_dict[data.uuid] = nil
        end

        ngx.log(ngx.DEBUG, "buffer reset")
        return
      end

      if buffer == nil then
        buf = string_buffer.new(PAYLOAD_MAX_LEN * 2)
        buffer_dict[data.uuid] = { buffer = buf, ts = nil }
      end

      buf:put(data.data)
      buffer.ts = ngx.now()
      if data.length ~= nil then
        assert(#buf == data.length, "failed to decode event payload: length mismatch")
        local d = buf:get(data.length)
        if data.serialized == 1 then
          d = cjson.decode(d)
        end

        buf:reset()
        buffer_dict[data.uuid] = nil
        assert(d, "failed to decode event payload")
        return callback(d, ...)
      end
    end

    return native_register(cb, source, event, ...)
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
