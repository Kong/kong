local cjson = require "cjson.safe"
local utils = require "kong.tools.utils"
local constants = require "kong.constants"
local counter = require "resty.counter"


local kong_dict = ngx.shared.kong
local ngx = ngx
local tcp_sock = ngx.socket.tcp
local timer_at = ngx.timer.at
local ngx_log = ngx.log
local var = ngx.var
local subsystem = ngx.config.subsystem
local concat = table.concat
local tostring = tostring
local lower = string.lower
local pairs = pairs
local error = error
local type = type
local WARN = ngx.WARN
local sub = string.sub


local PING_INTERVAL = 3600
local PING_KEY = "events:reports"


local REQUEST_COUNT_KEY       = "events:requests"
local HTTP_REQUEST_COUNT_KEY  = "events:requests:http"
local HTTPS_REQUEST_COUNT_KEY = "events:requests:https"
local H2C_REQUEST_COUNT_KEY   = "events:requests:h2c"
local H2_REQUEST_COUNT_KEY    = "events:requests:h2"
local GRPC_REQUEST_COUNT_KEY  = "events:requests:grpc"
local GRPCS_REQUEST_COUNT_KEY = "events:requests:grpcs"
local WS_REQUEST_COUNT_KEY    = "events:requests:ws"
local WSS_REQUEST_COUNT_KEY   = "events:requests:wss"


local STREAM_COUNT_KEY        = "events:streams"
local TCP_STREAM_COUNT_KEY    = "events:streams:tcp"
local TLS_STREAM_COUNT_KEY    = "events:streams:tls"


local GO_PLUGINS_REQUEST_COUNT_KEY = "events:requests:go_plugins"


local _buffer = {}
local _ping_infos = {}
local _enabled = false
local _unique_str = utils.random_string()
local _buffer_immutable_idx

-- the resty.counter instance, will be initialized in `init_worker`
local report_counter = nil

do
  -- initialize immutable buffer data (the same for each report)

  local meta = require "kong.meta"

  local system_infos = utils.get_system_infos()

  -- <14>: syslog facility code 'log alert'
  _buffer[#_buffer + 1] = "<14>version=" .. meta._VERSION

  for k, v in pairs(system_infos) do
    _buffer[#_buffer + 1] = k .. "=" .. v
  end

  _buffer_immutable_idx = #_buffer -- max idx for immutable slots
end


local function log(lvl, ...)
  ngx_log(lvl, "[reports] ", ...)
end


local function serialize_report_value(v)
  if type(v) == "function" then
    v = v()
  end

  if type(v) == "table" then
    local json, err = cjson.encode(v)
    if err then
      log(WARN, "could not JSON encode given table entity: ", err)
    end

    v = json
  end

  return v ~= nil and tostring(v) or nil
end


-- TCP logger


local function send_report(signal_type, t, host, port)
  if not _enabled then
    return
  elseif type(signal_type) ~= "string" then
    return error("signal_type (arg #1) must be a string", 2)
  end

  t = t or {}
  host = host or constants.REPORTS.ADDRESS
  port = port or constants.REPORTS.STATS_PORT

  -- add signal type to data

  t.signal = signal_type

  -- insert given entity in mutable part of buffer

  local mutable_idx = _buffer_immutable_idx

  for k, v in pairs(t) do
    if k == "unique_id" or (k ~= "created_at" and sub(k, -2) ~= "id") then
      v = serialize_report_value(v)
      if v ~= nil then
        mutable_idx = mutable_idx + 1
        _buffer[mutable_idx] = k .. "=" .. v
      end
    end
  end

  local sock = tcp_sock()
  sock:settimeouts(30000, 30000, 30000)

  -- errors are not logged to avoid false positives for users
  -- who run Kong in an air-gapped environments

  local ok = sock:connect(host, port)
  if not ok then
    return
  end

  sock:send(concat(_buffer, ";", 1, mutable_idx) .. "\n")
  sock:setkeepalive()
end


-- ping timer handler


-- Hold a lock for the whole interval (exptime) to prevent multiple
-- worker processes from sending the test request simultaneously.
-- Other workers do not need to wait until this lock is released,
-- and can ignore the event, knowing another worker is handling it.
-- We subtract 1ms to the exp time to prevent a race condition
-- with the next timer event.
local function get_lock(key, exptime)
  local ok, err = kong_dict:safe_add(key, true, exptime - 0.001)
  if not ok and err ~= "exists" then
    log(WARN, "could not get lock from 'kong' shm: ", err)
  end

  return ok
end


local function create_timer(...)
  local ok, err = timer_at(...)
  if not ok then
    log(WARN, "could not create ping timer: ", err)
  end
end

-- @param interval exposed for unit test only
local function create_counter(interval)
  local err
  -- create a counter instance which syncs to `kong` shdict every 10 minutes
  report_counter, err = counter.new('kong', interval or 600)
  return err
end


local function get_counter(key)
  local count, err = report_counter:get(key)
  if err then
    log(WARN, "could not get ", key, " from 'kong' shm: ", err)
  end
  return count or 0
end


local function reset_counter(key, amount)
  local ok, err = report_counter:reset(key, amount)
  if not ok then
    log(WARN, "could not reset ", key, " in 'kong' shm: ", err)
  end
end


local function incr_counter(key)
  local ok, err = report_counter:incr(key, 1)
  if not ok then
    log(WARN, "could not increment ", key, " in 'kong' shm: ", err)
  end
end


-- returns a string indicating the "kind" of the current request/stream:
-- "http", "https", "h2c", "h2", "grpc", "grpcs", "ws", "wss", "tcp", "tls"
-- or nil + error message if the suffix could not be determined
local function get_current_suffix()
  if subsystem == "stream" then
    if var.ssl_protocol then
      return "tls"
    end

    return "tcp"
  end

  local scheme = var.scheme
  if scheme == "http" or scheme == "https" then
    local proxy_mode = var.kong_proxy_mode
    if proxy_mode == "http" then
      local http_upgrade = var.http_upgrade
      if http_upgrade and lower(http_upgrade) == "websocket" then
        if scheme == "http" then
          return "ws"
        end

        return "wss"
      end

      if ngx.req.http_version() == 2 then
        if scheme == "http" then
          return "h2c"
        end

        return "h2"
      end

      return scheme
    end

    if proxy_mode == "grpc" then
      if scheme == "http" then
        return "grpc"
      end

      if scheme == "https" then
        return "grpcs"
      end
    end
  end

  return nil, "unknown request scheme: " .. tostring(scheme)
end


local function send_ping(host, port)
  _ping_infos.unique_id = _unique_str

  if subsystem == "stream" then
    _ping_infos.streams     = get_counter(STREAM_COUNT_KEY)
    _ping_infos.tcp_streams = get_counter(TCP_STREAM_COUNT_KEY)
    _ping_infos.tls_streams = get_counter(TLS_STREAM_COUNT_KEY)
    _ping_infos.go_plugin_reqs = get_counter(GO_PLUGINS_REQUEST_COUNT_KEY)

    send_report("ping", _ping_infos, host, port)

    reset_counter(STREAM_COUNT_KEY, _ping_infos.streams)
    reset_counter(TCP_STREAM_COUNT_KEY, _ping_infos.tcp_streams)
    reset_counter(TLS_STREAM_COUNT_KEY, _ping_infos.tls_streams)
    reset_counter(GO_PLUGINS_REQUEST_COUNT_KEY, _ping_infos.go_plugin_reqs)

    return
  end

  _ping_infos.requests       = get_counter(REQUEST_COUNT_KEY)
  _ping_infos.http_reqs      = get_counter(HTTP_REQUEST_COUNT_KEY)
  _ping_infos.https_reqs     = get_counter(HTTPS_REQUEST_COUNT_KEY)
  _ping_infos.h2c_reqs       = get_counter(H2C_REQUEST_COUNT_KEY)
  _ping_infos.h2_reqs        = get_counter(H2_REQUEST_COUNT_KEY)
  _ping_infos.grpc_reqs      = get_counter(GRPC_REQUEST_COUNT_KEY)
  _ping_infos.grpcs_reqs     = get_counter(GRPCS_REQUEST_COUNT_KEY)
  _ping_infos.ws_reqs        = get_counter(WS_REQUEST_COUNT_KEY)
  _ping_infos.wss_reqs       = get_counter(WSS_REQUEST_COUNT_KEY)
  _ping_infos.go_plugin_reqs = get_counter(GO_PLUGINS_REQUEST_COUNT_KEY)

  send_report("ping", _ping_infos, host, port)

  reset_counter(REQUEST_COUNT_KEY,       _ping_infos.requests)
  reset_counter(HTTP_REQUEST_COUNT_KEY,  _ping_infos.http_reqs)
  reset_counter(HTTPS_REQUEST_COUNT_KEY, _ping_infos.https_reqs)
  reset_counter(H2C_REQUEST_COUNT_KEY,   _ping_infos.h2c_reqs)
  reset_counter(H2_REQUEST_COUNT_KEY,    _ping_infos.h2_reqs)
  reset_counter(GRPC_REQUEST_COUNT_KEY,  _ping_infos.grpc_reqs)
  reset_counter(GRPCS_REQUEST_COUNT_KEY, _ping_infos.grpcs_reqs)
  reset_counter(WS_REQUEST_COUNT_KEY,    _ping_infos.ws_reqs)
  reset_counter(WSS_REQUEST_COUNT_KEY,   _ping_infos.wss_reqs)
  reset_counter(GO_PLUGINS_REQUEST_COUNT_KEY, _ping_infos.go_plugin_reqs)
end


local function ping_handler(premature)
  if premature then
    return
  end

  -- all workers need to register a recurring timer, in case one of them
  -- crashes. Hence, this must be called before the `get_lock()` call.
  create_timer(PING_INTERVAL, ping_handler)

  if not get_lock(PING_KEY, PING_INTERVAL) then
    return
  end

  send_ping()
end


local function add_ping_value(k, v)
  _ping_infos[k] = v
end


local function add_immutable_value(k, v)
  v = serialize_report_value(v)
  if v ~= nil then
    _buffer_immutable_idx = _buffer_immutable_idx + 1
    _buffer[_buffer_immutable_idx] = k .. "=" .. v
  end
end


local function configure_ping(kong_conf)
  if type(kong_conf) ~= "table" then
    error("kong_config must be a table", 2)
  end

  add_immutable_value("database", kong_conf.database)
  add_immutable_value("role", kong_conf.role)
  add_immutable_value("kic", kong_conf.kic)
  add_immutable_value("_admin", #kong_conf.admin_listeners > 0 and 1 or 0)
  add_immutable_value("_proxy", #kong_conf.proxy_listeners > 0 and 1 or 0)
  add_immutable_value("_stream", #kong_conf.stream_listeners > 0 and 1 or 0)
end


local retrieve_redis_version


do
  local _retrieved_redis_version = false
  retrieve_redis_version = function(red)
    if not _enabled or _retrieved_redis_version then
      return
    end

    -- we will run this branch for each worker's first hit, but never
    -- again. Hopefully someday Redis will be made a first class citizen
    -- in Kong and its integration can be tied deeper into the core,
    -- avoiding such "hacks".
    _retrieved_redis_version = true

    local redis_version

    -- This logic should work for Redis >= 2.4.
    local res, err = red:info("server")
    if type(res) ~= "string" then
      -- could be nil or ngx.null
      ngx_log(WARN, "failed to retrieve Redis version: ", err)

    else
      -- retrieve first 2 digits only
      redis_version = res:match("redis_version:(%d+%.%d+).-\r\n")
    end

    add_ping_value("redis_version", redis_version or "unknown")
  end
end


return {
  -- plugin handler
  init_worker = function()
    if not _enabled then
      return
    end

    create_timer(PING_INTERVAL, ping_handler)

    local err = create_counter()
    if err then
      error(err)
    end
  end,
  add_immutable_value = add_immutable_value,
  configure_ping = configure_ping,
  add_ping_value = add_ping_value,
  get_ping_value = function(k)
    return _ping_infos[k]
  end,
  send_ping = send_ping,
  log = function(ctx)
    if not _enabled then
      return
    end

    local count_key = subsystem == "stream" and STREAM_COUNT_KEY
                                             or REQUEST_COUNT_KEY

    incr_counter(count_key)
    local suffix, err = get_current_suffix()
    if suffix then
      incr_counter(count_key .. ":" .. suffix)

      if ctx.ran_go_plugin then
        incr_counter(GO_PLUGINS_REQUEST_COUNT_KEY)
      end
    else
      log(WARN, err)
    end
  end,

  -- custom methods
  toggle = function(enable)
    _enabled = enable
  end,
  send = send_report,
  retrieve_redis_version = retrieve_redis_version,
  -- exposed for unit test
  _create_counter = create_counter,
  -- exposed for integration test
  _sync_counter = function() report_counter:sync() end,
}
