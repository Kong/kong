-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local messaging = require "kong.tools.messaging"

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

local SHM_KEY = "vitals-clustering-buffer"
local SHM = ngx.shared.kong

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
    if self.hybrid_cp then
      error("Cannot use this function in control plane", 2)
    end
    -- for status code we don't set the `flush_now` (3rd parameter) to
    -- allow aggregation
    return self.messaging:send_message(t, data)
  end
  datasets_lookup[t] = f
end

-- CP function
local function init_node_meta(real_strategy, node_id, node_hostname)
  local meta, err = real_strategy:select_node_meta({ node_id })
  if err then
    return false, err
  elseif meta and #meta > 0 then
    return false
  end

  return real_strategy:init(node_id, node_hostname)
end

local cp_functions = {
  "select_stats", "select_node_meta", "select_phone_home", "select_consumer_stats",
  "select_status_codes_by_service", "select_status_codes_by_route", "select_status_codes_by_consumer",
  "select_status_codes_by_consumer_and_route", "select_status_codes",
  "node_exists", "interval_width",
}
for _, f in ipairs(cp_functions) do
  _M[f] = function(self, ...)
    if not self.hybrid_cp then
      error("Cannot use this function in data plane", 2)
    end

    return self.real_strategy[f](self.real_strategy, ...)
  end
end

local dp_functions = {}

for _, f in ipairs(dp_functions) do
  _M[f] = function(self, ...)
    if self.hybrid_cp then
      error("Cannot use this function in control plane", 2)
    end

    return self.real_strategy[f](self.real_strategy, ...)
  end
end



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

local function get_serve_ingest_func(self)
  local real_strategy = self.real_strategy
  return function(payload)
    if not kong.configuration.vitals then
      ngx.log(ngx.WARN, _log_prefix, "received telemetry from data plane, ",
        "but vitals is not enabled on control plane")
      -- disconnect websocket
      return ngx.exit(ngx.ERROR)
    end

    if not self.hybrid_cp then
      error("Cannot use this function in data plane", 2)
    end

    local node_id = ngx.var.arg_node_id
    local node_hostname = ngx.var.arg_node_hostname
    if node_id == "" or node_hostname == "" then
      ngx.log(ngx.ERR, _log_prefix, "node_id or node_hostname not exist in query")
      return ngx.exit(400)
    end

    local ok, err = init_node_meta(real_strategy, node_id, node_hostname)
    if err then
      ngx.log(ngx.WARN, _log_prefix, "failed to store node meta with ID: ", node_id,
                                  ", hostname: ", node_hostname, ", err: ", err)
    elseif ok then
      ngx.log(ngx.DEBUG, _log_prefix, "new node meta stored with ID: ", node_id, ", hostname: ", node_hostname)
    end

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
        local ok, err = real_strategy:insert_stats(flush_data)
        if not ok then
          ngx.log(ngx.ERR, _log_prefix, "error writing: ", err)
        end

        ngx.log(ngx.DEBUG, _log_prefix, "delete expired stats")
        local expiries = {
          minutes = kong.vitals.ttl_minutes,
        }
        local ok, err = real_strategy:delete_stats(expiries)
        if not ok then
          ngx.log(ngx.WARN, _log_prefix, "failed to delete stats: ", err)
        end
      else
        local f = datasets_lookup[stats_type]
        if f then
          real_strategy[f](real_strategy, flush_data)
        else
          ngx.log(ngx.ERR, _log_prefix, "unknown vitals type ", stats_type)
        end
      end
    end
  end
end

function _M.new(db, opts)
  local hybrid_cp = kong.configuration.role == "control_plane"

  local self = {
    hybrid_cp = hybrid_cp,
  }

  if hybrid_cp then
    local strategy
    if db.strategy == "postgres" then
      strategy = require "kong.vitals.postgres.strategy"
    elseif db.strategy == "cassandra" then
      strategy = require "kong.vitals.cassandra.strategy"
    else
      error("Unsupported db stragey " .. (db.strategy or "nil"), 2)
    end

    self.real_strategy = strategy.new(db, opts)
  end

  local messaging, err = messaging.new({
    type = hybrid_cp and messaging.TYPE.CONSUMER or messaging.TYPE.PRODUCER,
    cluster_endpoint = kong.configuration.cluster_telemetry_endpoint,
    message_type = TELEMETRY_TYPE,
    message_type_version = TELEMETRY_VERSION,
    serve_ingest_func = get_serve_ingest_func(self),
    shm = SHM,
    shm_key = SHM_KEY,
  })

  if not messaging then
    return nil, err
  end

  self.messaging = messaging;

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

function _M:insert_stats(flush_data)
  if self.hybrid_cp then
    error("Cannot use this function in control plane", 2)
  end

  return self.messaging:send_message(VITALS_TYPE_STATS, flush_data, true)
end

function _M:delete_stats(...)
  if self.hybrid_cp then
    error("Cannot use this function in control plane", 2)
  end
  -- noop
  return true, nil
end

function _M:select_phone_home(...)
  if not self.is_cp then
    error("Cannot use this function in data plane", 2)
  end

  ngx.log(ngx.WARN, "phone home is not yet implemented on Hybrid control plane")
  return {}, nil
end

return _M
