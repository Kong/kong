local new_tab = require("table.new")
local clear_tab = require("table.clear")

local utils = require("kong.tools.utils")
local msgpack = require "MessagePack"
local mp_pack = msgpack.pack
local mp_unpack = msgpack.unpack
local cjson_encode = require "cjson".encode
local clustering = require "kong.clustering"

local _M = {}
local mt = { __index = _M }

local _log_prefix = "[vitals-strategy] "

local TELEMETRY_VERSION = "v1"
local TELEMETRY_TYPE = "vitals"

local VITALS_TYPE_STATS = 0x1
local VITALS_TYPE_STATUS_CODE_BY_SERVICE = 0x2
local VITALS_TYPE_STATUS_CODE_BY_ROUTE = 0x4
local VITALS_TYPE_STATUS_CODE_BY_CONSUMER_AND_ROUTE = 0x8
local VITALS_TYPE_STATUS_CODE_CLASSES = 0x10
local VITALS_TYPE_STATUS_CODE_BY_WORKSPACE = 0x20
local VITALS_TYPE_CONSUMER_STATS = 0x40

-- maximum elements count in buffer to trigger force flush
local BUFFER_SIZE = 64
local buffer = new_tab(BUFFER_SIZE, 0)
local buffer_idx = 1
-- the unix timestamp when buffer created
local buffer_age = 0
-- how old can a buffer survive before being flushed
-- currently 1/4 of normal database strategy flush ttl
local BUFFER_TTL = 2
-- in case of failure, how long of history should we keep
-- before start to drop. BUFFER_RETRY_SIZE * BUFFER_TTL
-- is the roughly time we want of keep for unsent metrics
local BUFFER_RETRY_SIZE = 60
local SHM_KEY = "vitals-clustering-buffer"
local SHM = ngx.shared.kong

local ws_send_func

local dummy_heartbeat_msg = cjson_encode({
  type = TELEMETRY_TYPE,
  -- TODO: msgid for re-transmit
  -- cjson decodes nil to lightuserdata null, this is unhandled
  -- in db strategies, to avoid introducing too much change we
  -- use mp_pack to wrap inner payloads
  data = mp_pack({
    TELEMETRY_VERSION,
    TELEMETRY_TYPE,
    {},
  }),
})

local dummy_response_msg = "PONG"

local function flush_cp(premature)
  if premature then
    return
  end

  local sent = false

  if ws_send_func then
    while true do
      local v, err = SHM:rpop(SHM_KEY)
      if err then
        ngx.log(ngx.WARN, _log_prefix, "cannot get rpop shm buffer: ", err)
        break
      elseif v == nil then
        break
      end

      local _, err = ws_send_func(v)
      if err then
        local _, err = SHM:lpush(SHM_KEY, v)
        ngx.log(ngx.WARN, _log_prefix, "cannot putting back to shm buffer: ", err)
        break
      end
      sent = true

      ngx.log(ngx.DEBUG, _log_prefix, "flush ", #v, " bytes to CP")
    end

    -- this is like a ping in case no other data is produced
    if not sent then
      ws_send_func(dummy_heartbeat_msg)
    end
  else
    ngx.log(ngx.DEBUG, _log_prefix, "websocket is not ready yet, waiting for next try")
  end


  local len, err = SHM:llen(SHM_KEY)
  if err then
    ngx.log(ngx.WARN, _log_prefix, "cannot get length of shm buffer: ", err)
  elseif len > BUFFER_RETRY_SIZE then
    ngx.log(ngx.WARN, _log_prefix, "cleaned up ", len - BUFFER_RETRY_SIZE, " unflushed buffer")
    for _=0, len - BUFFER_RETRY_SIZE do
      SHM:rpop(SHM_KEY)
    end
  end

  assert(ngx.timer.at(BUFFER_TTL, flush_cp))

end

function _M.new(db, opts)
  local is_cp = kong.configuration.role == "control_plane"

  local self = {
    is_cp = is_cp,
  }

  if is_cp then
    local strategy
    if db.strategy == "postgres" then
      strategy = require "kong.vitals.postgres.strategy"
    elseif db.strategy == "cassandra" then
      strategy = require "kong.vitals.postgres.strategy"
    else
      error("Unsupported db stragey " .. (db.strategy or "nil"), 2)
    end

    self.real_strategy = strategy.new(db, opts)

    clustering.register_server_on_message(TELEMETRY_TYPE, function(...)
      self:serve_ingest(...)
    end)
  else
    local m, _ = ngx.re.match(kong.configuration.cluster_telemetry_endpoint, [[([^:]+):(\d+)]])
    if m then
      self.host = m[1]
      self.port = tonumber(m[2])
    end

    if not self.host or not self.port then
      error("Malformed cluster_telemetry_endpoint", 2)
    end
  end

  return setmetatable(self, mt)
end

local function start_ws_client()
  local conf = kong.configuration
  local address = conf.cluster_telemetry_endpoint

  local uri = "wss://" .. address .. "/v1/ingest?node_id=" ..
              kong.node.get_id() .. "&node_hostname=" .. utils.get_hostname()
  local server_name
  if conf.cluster_mtls == "shared" then
    server_name = "kong_clustering"
  else
    -- server_name will be set to the host if it is not explicitly defined here
    if conf.cluster_server_name ~= "" then
      server_name = conf.cluster_server_name
    end
  end

  assert(ngx.timer.at(0, clustering.communicate, uri, server_name, function(connected, send_func)
    if connected then
      ngx.log(ngx.DEBUG, _log_prefix, "telemetry websocket is connected")
      ws_send_func = send_func
    else
      ngx.log(ngx.DEBUG, _log_prefix, "telemetry websocket is disconnected")
      ws_send_func = nil
    end
  end))
end

function _M:init(...)
  if not self.is_cp then
    if ngx.worker.id() == 0 then
      start_ws_client()

      assert(ngx.timer.at(BUFFER_TTL, flush_cp))
    end
    return true
  end
  return self.real_strategy:init(...)
end

local function store_buffer(typ, data, flush_now)

  if buffer_idx == 1 then
    buffer_age = ngx.now()
  end
  buffer[buffer_idx] = typ
  buffer[buffer_idx+1] = data
  buffer_idx = buffer_idx + 2

  if not flush_now then
    ngx.update_time()
    -- TODO: this relies on the behaviour of timer of vitals and node_stats is flushed
    -- every 10 seconds.
    if buffer_idx < BUFFER_SIZE and ngx.now() - buffer_age < BUFFER_TTL then
      return true
    end
  end

  local data = cjson_encode({
    type = TELEMETRY_TYPE,
    -- TODO: msgid for re-transmit
    -- cjson decodes nil to lightuserdata null, this is unhandled
    -- in db strategies, to avoid introducing too much change we
    -- use mp_pack to wrap inner payloads
    data = mp_pack({
      TELEMETRY_VERSION,
      TELEMETRY_TYPE,
      buffer,
    }),
  })
  buffer_idx = 1
  clear_tab(buffer)

  local _, err = SHM:lpush(SHM_KEY, data)
  if err then
    return false, err
  end

  return true
end

function _M:insert_stats(flush_data)
  if self.is_cp then
    error("Cannot use this function in control plane", 2)
  end

  return store_buffer(VITALS_TYPE_STATS, flush_data, true)
end

function _M:delete_stats(...)
  if self.is_cp then
    error("Cannot use this function in control plane", 2)
  end
  -- noop
  return true, nil
end


local datasets = {
  insert_status_codes_by_service = VITALS_TYPE_STATUS_CODE_BY_SERVICE,
  insert_status_codes_by_route = VITALS_TYPE_STATUS_CODE_BY_ROUTE,
  insert_status_codes_by_consumer_and_route = VITALS_TYPE_STATUS_CODE_BY_CONSUMER_AND_ROUTE,
  insert_status_code_classes = VITALS_TYPE_STATUS_CODE_CLASSES,
  insert_status_code_classes_by_workspace = VITALS_TYPE_STATUS_CODE_BY_WORKSPACE,
  insert_consumer_stats = VITALS_TYPE_CONSUMER_STATS,
}

local datasets_lookup = {}

for f, t in pairs(datasets) do
  _M[f] = function(self, data)
    if self.is_cp then
      error("Cannot use this function in control plane", 2)
    end
    -- for status code we don't set the `flush_now` (3rd parameter) to
    -- allow aggregation
    return store_buffer(t, data)
  end
  datasets_lookup[t] = f
end

function _M:serve_ingest(msg, queued_send)
  if not kong.configuration.vitals then
    ngx.log(ngx.WARN, _log_prefix, "received telemetry from data plane, ",
            "but vitals is not enabled on control plane")
    -- disconnect websocket
    return ngx.exit(ngx.ERROR)
  end

  if not self.is_cp then
    error("Cannot use this function in data plane", 2)
  end

  local v, t, payload = unpack(mp_unpack(msg.data))
  if v ~= TELEMETRY_VERSION or t ~= TELEMETRY_TYPE then
    ngx.log(ngx.ERR, _log_prefix, "ingest version or type doesn't match, ",
      "expect version ", TELEMETRY_VERSION, " type ", TELEMETRY_TYPE, ", ",
      "got version ", v, " type ", t)
    return ngx.exit(400)
  end

  -- just send a empty response for now
  -- this can be implemented into a per msgid retry in the future
  queued_send(dummy_response_msg)

  if #payload == 0 then
    return
  end

  ngx.log(ngx.DEBUG, "recv size ", #msg.data, " sets ", #payload/2)

  local idx = 1
  local stats_type, flush_data
  while true do
    stats_type = payload[idx]
    flush_data = payload[idx+1]
    if not stats_type or not flush_data then
      break
    end
    idx = idx + 2

    ngx.log(ngx.DEBUG, _log_prefix, "processing type ", stats_type)

    if stats_type == VITALS_TYPE_STATS then
      local ok, err = self.real_strategy:insert_stats(flush_data)
      if not ok then
        ngx.log(ngx.ERR, _log_prefix, "error writing: ", err)
      end

      ngx.log(ngx.DEBUG, _log_prefix, "delete expired stats")
      local expiries = {
        minutes = kong.vitals.ttl_minutes,
      }
      local ok, err = self.real_strategy:delete_stats(expiries)
      if not ok then
        ngx.log(ngx.WARN, _log_prefix, "failed to delete stats: ", err)
      end
    else
      local f = datasets_lookup[stats_type]
      if f then
        self.real_strategy[f](self.real_strategy, flush_data)
      else
        ngx.log(ngx.ERR, _log_prefix, "unknown vitals type ", stats_type)
      end
    end
  end
end

local cp_functions = {
  "select_stats", "select_node_meta", "select_phone_home", "select_consumer_stats",
  "select_status_codes_by_service", "select_status_codes_by_route", "select_status_codes_by_consumer",
  "select_status_codes_by_consumer_and_route", "select_status_codes",
  "node_exists", "interval_width",
}
for _, f in ipairs(cp_functions) do
  _M[f] = function(self, ...)
    if not self.is_cp then
      error("Cannot use this function in data plane", 2)
    end

    return self.real_strategy[f](self.real_strategy, ...)
  end
end

local dp_functions = {}

for _, f in ipairs(dp_functions) do
  _M[f] = function(self, ...)
    if self.is_cp then
      error("Cannot use this function in control plane", 2)
    end

    return self.real_strategy[f](self.real_strategy, ...)
  end
end

return _M
