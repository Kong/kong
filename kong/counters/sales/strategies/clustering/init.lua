local messaging = require "kong.tools.messaging"

local _M = {}
local mt = { __index = _M }

local _log_prefix = "[counters-strategy] "

local TELEMETRY_VERSION = "v1"
local TELEMETRY_TYPE = "counters"

local COUNTERS_TYPE_STATS = 0x1

local dummy_response_msg = "PONG"

local SHM_KEY = "counters-clustering-buffer"
local SHM = ngx.shared.kong

local function get_server_name()
  local conf = kong.configuration
  local server_name
  if conf.cluster_mtls == "shared" then
    server_name = "kong_clustering"
  else
    -- server_name will be set to the host if it is not explicitly defined here
    if conf.cluster_telemetry_server_name ~= "" then
      server_name = conf.cluster_telemetry_server_name
    elseif conf.cluster_server_name ~= "" then
      server_name = conf.cluster_server_name
    end
  end
  return server_name
end

local function serve_ingest(self, msg, queued_send)
  if self.type == self.TYPE.PRODUCER then
    error("Cannot use this function in data plane", 2)
  end

  local payload, err = self:unpack_message(msg)
  if err then
    ngx.log(ngx.ERR, _log_prefix, err)
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

    if stats_type == COUNTERS_TYPE_STATS then
      local _, err = self.serve_ingest_args.real_strategy:flush_data(flush_data)
      if err then
        ngx.log(ngx.ERR, _log_prefix, "error writing: ", err)
      end
    end
  end
end


function _M.new(db, opts)
  local hybrid_cp = kong.configuration.role == "control_plane"
  local messaging, err = messaging:new({
    type = hybrid_cp and messaging.TYPE.CONSUMER or messaging.TYPE.PRODUCER,
    cluster_endpoint = kong.configuration.cluster_telemetry_endpoint,
    message_type = TELEMETRY_TYPE,
    message_type_version = TELEMETRY_VERSION,
    serve_ingest_func = serve_ingest,
    serve_ingest_func_args = {
      real_strategy = db,
    },
    shm = SHM,
    shm_key = SHM_KEY,
  })

  if not messaging then
    return nil, err
  end

  local self = {
    hybrid_cp = hybrid_cp,
    messaging = messaging
  }

  if hybrid_cp then
    self.real_strategy = db
  end

  return setmetatable(self, mt)
end

function _M:init(...)
  if not self.hybrid_cp then
    if ngx.worker.id() == 0 then
      -- start client to produce messages
      self.messaging:start_client(get_server_name())
    end
    return true
  end
  -- start server to listen for messages
  self.messaging:register_for_messages()
  return self.real_strategy:init(...)
end

function _M:pull_data()
  return self.real_strategy:pull_data()
end

function _M:flush_data(data)
  if self.hybrid_cp then
    error("Cannot use this function in control plane", 2)
  end
  return self.messaging:send_message(COUNTERS_TYPE_STATS, data)
end

return _M
