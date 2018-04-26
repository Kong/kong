local cjson = require "cjson.safe"
local utils = require "kong.tools.utils"
local constants = require "kong.constants"


local kong_dict = ngx.shared.kong
local udp_sock = ngx.socket.udp
local timer_at = ngx.timer.at
local ngx_log = ngx.log
local concat = table.concat
local tostring = tostring
local pairs = pairs
local type = type
local WARN = ngx.WARN
local sub = string.sub


local PING_INTERVAL = 3600
local PING_KEY = "events:reports"
local BUFFERED_REQUESTS_COUNT_KEYS = "events:requests"


local _buffer = {}
local _ping_infos = {}
local _enabled = false
local _unique_str = utils.random_string()
local _buffer_immutable_idx


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


-- UDP logger


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

  local sock = udp_sock()
  local ok, err = sock:setpeername(host, port)
  if not ok then
    log(WARN, "could not set peer name for UDP socket: ", err)
    return
  end

  sock:settimeout(1000)

  -- concat and send buffer

  ok, err = sock:send(concat(_buffer, ";", 1, mutable_idx))
  if not ok then
    log(WARN, "could not send data: ", err)
  end

  ok, err = sock:close()
  if not ok then
    log(WARN, "could not close socket: ", err)
  end
end


-- ping timer handler


-- Hold a lock for the whole interval (exptime) to prevent multiple
-- worker processes from sending the test request simultaneously.
-- Other workers do not need to wait until this lock is released,
-- and can ignore the event, knowing another worker is handling it.
-- We substract 1ms to the exp time to prevent a race condition
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

  local n_requests, err = kong_dict:get(BUFFERED_REQUESTS_COUNT_KEYS)
  if err then
    log(WARN, "could not get buffered requests count from 'kong' shm: ", err)
  elseif not n_requests then
    n_requests = 0
  end

  _ping_infos.requests = n_requests
  _ping_infos.unique_id = _unique_str

  send_report("ping", _ping_infos)

  local ok, err = kong_dict:incr(BUFFERED_REQUESTS_COUNT_KEYS, -n_requests, n_requests)
  if not ok then
    log(WARN, "could not reset buffered requests count in 'kong' shm: ", err)
  end
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
  end,
  add_immutable_value = add_immutable_value,
  add_ping_value = add_ping_value,
  get_ping_value = function(k)
    return _ping_infos[k]
  end,
  log = function()
    if not _enabled then
      return
    end

    local ok, err = kong_dict:incr(BUFFERED_REQUESTS_COUNT_KEYS, 1, 0)
    if not ok then
      log(WARN, "could not increment buffered requests count in 'kong' shm: ",
                err)
    end
  end,

  -- custom methods
  toggle = function(enable)
    _enabled = enable
  end,
  send = send_report,
  retrieve_redis_version = retrieve_redis_version,
}
