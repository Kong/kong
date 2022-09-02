local _M = {}
local _MT = { __index = _M, }


local semaphore = require("ngx.semaphore")
local cjson = require("cjson.safe")
local declarative = require("kong.db.declarative")
local constants = require("kong.constants")
local clustering_utils = require("kong.clustering.utils")
local wrpc = require("kong.tools.wrpc")
local wrpc_proto = require("kong.tools.wrpc.proto")
local utils = require("kong.tools.utils")
local init_negotiation_server = require("kong.clustering.services.negotiation").init_negotiation_server
local calculate_config_hash = require("kong.clustering.config_helper").calculate_config_hash
local string = string
local setmetatable = setmetatable
local pcall = pcall
local pairs = pairs
local ngx = ngx
local ngx_log = ngx.log
local cjson_encode = cjson.encode
local kong = kong
local ngx_exit = ngx.exit
local exiting = ngx.worker.exiting
local ngx_time = ngx.time
local ngx_var = ngx.var
local timer_at = ngx.timer.at
local isempty = require("table.isempty")

local plugins_list_to_map = clustering_utils.plugins_list_to_map
local deflate_gzip = utils.deflate_gzip
local yield = utils.yield

local kong_dict = ngx.shared.kong
local ngx_DEBUG = ngx.DEBUG
local ngx_INFO = ngx.INFO
local ngx_NOTICE = ngx.NOTICE
local ngx_ERR = ngx.ERR
local ngx_WARN = ngx.WARN
local ngx_CLOSE = ngx.HTTP_CLOSE
local CLUSTERING_SYNC_STATUS = constants.CLUSTERING_SYNC_STATUS
local _log_prefix = "[wrpc-clustering] "

local ok_table = { ok = "done", }
local initial_hash = string.rep("0", 32)
local empty_table = {}


local function handle_export_deflated_reconfigure_payload(self)
  local ok, p_err, err = pcall(self.export_deflated_reconfigure_payload, self)
  return ok, p_err or err
end

local function init_config_service(wrpc_service, cp)
  wrpc_service:import("kong.services.config.v1.config")

  wrpc_service:set_handler("ConfigService.PingCP", function(peer, data)
    local client = cp.clients[peer.conn]
    if client and client.update_sync_status then
      client.last_seen = ngx_time()
      client.config_hash = data.hash
      client:update_sync_status()
      ngx_log(ngx_INFO, _log_prefix, "received ping frame from data plane")
    end
  end)

  wrpc_service:set_handler("ConfigService.ReportMetadata", function(peer, data)
    local client = peer.client
    local cp = peer.cp
    if client then
      ngx_log(ngx_INFO, _log_prefix, "received initial metadata package from client: ", client.dp_id)
      client.basic_info = data
      client.dp_plugins_map = plugins_list_to_map(client.basic_info.plugins or empty_table)
      client.basic_info_semaphore:post()
    end

    local _, err
    _, err, client.sync_status = cp:check_version_compatibility(client.dp_version, client.dp_plugins_map, client.log_suffix)
    client:update_sync_status()
    if err then
      ngx_log(ngx_ERR, _log_prefix, err, client.log_suffix)
      client.basic_info = nil -- drop the connection
      return { error = err, }
    end

    return ok_table
  end)
end

local wrpc_service

local function get_wrpc_service(self)
  if not wrpc_service then
    wrpc_service = wrpc_proto.new()
    init_negotiation_server(wrpc_service, self.conf)
    init_config_service(wrpc_service, self)
  end

  return wrpc_service
end


function _M.new(conf, cert_digest)
  local self = {
    clients = setmetatable({}, { __mode = "k", }),
    plugins_map = {},

    conf = conf,
    cert_digest = cert_digest,
  }

  return setmetatable(self, _MT)
end


local config_version = 0

function _M:export_deflated_reconfigure_payload()
  ngx_log(ngx_DEBUG, _log_prefix, "exporting config")

  local config_table, err = declarative.export_config()
  if not config_table then
    return nil, err
  end

  -- update plugins map
  self.plugins_configured = {}
  if config_table.plugins then
    for _, plugin in pairs(config_table.plugins) do
      self.plugins_configured[plugin.name] = true
    end
  end

  local config_hash, hashes = calculate_config_hash(config_table)
  config_version = config_version + 1

  -- store serialized plugins map for troubleshooting purposes
  local shm_key_name = "clustering:cp_plugins_configured:worker_" .. ngx.worker.id()
  kong_dict:set(shm_key_name, cjson_encode(self.plugins_configured))

  local service = get_wrpc_service(self)

  -- yield between steps to prevent long delay
  local config_json = assert(cjson_encode(config_table))
  yield()
  local config_compressed = assert(deflate_gzip(config_json))
  yield()
  self.config_call_rpc, self.config_call_args = assert(service:encode_args("ConfigService.SyncConfig", {
    config = config_compressed,
    version = config_version,
    config_hash = config_hash,
    hashes = hashes,
  }))

  return config_table, nil
end

function _M:push_config_one_client(client)
  -- if clients table is empty, we might have skipped some config
  -- push event in `push_config_loop`, which means the cached config
  -- might be stale, so we always export the latest config again in this case
  if isempty(self.clients) or not self.config_call_rpc or not self.config_call_args then
    local ok, err = handle_export_deflated_reconfigure_payload(self)
    if not ok then
      ngx_log(ngx_ERR, _log_prefix, "unable to export config from database: ", err)
      return
    end
  end

  local ok, err, sync_status = self:check_configuration_compatibility(client.dp_plugins_map)
  if not ok then
    ngx_log(ngx_WARN, _log_prefix, "unable to send updated configuration to data plane: ", err, client.log_suffix)
    if sync_status ~= client.sync_status then
      client.sync_status = sync_status
      client:update_sync_status()
    end
    return
  end

  client.peer:send_encoded_call(self.config_call_rpc, self.config_call_args)
  ngx_log(ngx_DEBUG, _log_prefix, "config version #", config_version, " pushed.  ", client.log_suffix)
end

function _M:push_config()
  local payload, err = self:export_deflated_reconfigure_payload()
  if not payload then
    ngx_log(ngx_ERR, _log_prefix, "unable to export config from database: ", err)
    return
  end

  local n = 0
  for _, client in pairs(self.clients) do
    local ok, sync_status
    ok, err, sync_status = self:check_configuration_compatibility(client.dp_plugins_map)
    if ok then
      client.peer:send_encoded_call(self.config_call_rpc, self.config_call_args)
      n = n + 1
    else

      ngx_log(ngx_WARN, _log_prefix, "unable to send updated configuration to data plane: ", err, client.log_suffix)
      if sync_status ~= client.sync_status then
        client.sync_status = sync_status
        client:update_sync_status()
      end
    end
  end

  ngx_log(ngx_DEBUG, _log_prefix, "config version #", config_version, " pushed to ", n, " clients")
end


_M.check_version_compatibility = clustering_utils.check_version_compatibility
_M.check_configuration_compatibility = clustering_utils.check_configuration_compatibility


function _M:handle_cp_websocket()
  local dp_id = ngx_var.arg_node_id
  local dp_hostname = ngx_var.arg_node_hostname
  local dp_ip = ngx_var.remote_addr
  local dp_version = ngx_var.arg_node_version

  local wb, log_suffix, ec = clustering_utils.connect_dp(
                                self.conf, self.cert_digest,
                                dp_id, dp_hostname, dp_ip, dp_version)
  if not wb then
    return ngx_exit(ec)
  end

  -- connection established
  local w_peer = wrpc.new_peer(wb, get_wrpc_service(self))
  w_peer.id = dp_id
  local client = {
    last_seen = ngx_time(),
    peer = w_peer,
    dp_id = dp_id,
    dp_version = dp_version,
    log_suffix = log_suffix,
    basic_info = nil,
    basic_info_semaphore = semaphore.new(),
    dp_plugins_map = {},
    cp_ref = self,
    config_hash = initial_hash,
    sync_status = CLUSTERING_SYNC_STATUS.UNKNOWN,
  }
  w_peer.client = client
  w_peer.cp = self

  w_peer:spawn_threads()

  local purge_delay = self.conf.cluster_data_plane_purge_delay
  function client:update_sync_status()
    local ok, err = kong.db.clustering_data_planes:upsert({ id = dp_id, }, {
      last_seen = self.last_seen,
      config_hash = self.config_hash ~= "" and self.config_hash or nil,
      hostname = dp_hostname,
      ip = dp_ip,
      version = dp_version,
      sync_status = self.sync_status, -- TODO: import may have been failed though
    }, { ttl = purge_delay })
    if not ok then
      ngx_log(ngx_ERR, _log_prefix, "unable to update clustering data plane status: ", err, log_suffix)
    end
  end

  do
    local ok, err = client.basic_info_semaphore:wait(5)
    if not ok then
      err = "waiting for basic info call: " .. (err or "--")
    end
    if not client.basic_info then
      err = "invalid basic_info data"
    end

    if err then
      ngx_log(ngx_ERR, _log_prefix, err, log_suffix)
      wb:send_close()
      return ngx_exit(ngx_CLOSE)
    end
  end

  -- after basic_info report we consider DP connected
  -- initial sync
  client:update_sync_status()
  self:push_config_one_client(client)    -- first config push
  -- put it here to prevent DP from receiving broadcast config pushes before the first config pushing
  self.clients[w_peer.conn] = client

  ngx_log(ngx_NOTICE, _log_prefix, "data plane connected", log_suffix)
  w_peer:wait_threads()
  w_peer:close()
  self.clients[wb] = nil

  return ngx_exit(ngx_CLOSE)
end


local function push_config_loop(premature, self, push_config_semaphore, delay)
  if premature then
    return
  end

  do
    local ok, err = handle_export_deflated_reconfigure_payload(self)
    if not ok then
      ngx_log(ngx_ERR, _log_prefix, "unable to export initial config from database: ", err)
    end
  end

  while not exiting() do
    local ok, err = push_config_semaphore:wait(1)
    if exiting() then
      return
    end

    if ok then
      if isempty(self.clients) then
        ngx_log(ngx_DEBUG, _log_prefix, "skipping config push (no connected clients)")

      else
        ok, err = pcall(self.push_config, self)
        if ok then
          local sleep_left = delay
          while sleep_left > 0 do
            if sleep_left <= 1 then
              ngx.sleep(sleep_left)
              break
            end

            ngx.sleep(1)

            if exiting() then
              return
            end

            sleep_left = sleep_left - 1
          end

        else
          ngx_log(ngx_ERR, _log_prefix, "export and pushing config failed: ", err)
        end
      end

    elseif err ~= "timeout" then
      ngx_log(ngx_ERR, _log_prefix, "semaphore wait error: ", err)
    end
  end
end


function _M:init_worker(plugins_list)
  -- ROLE = "control_plane"
  self.plugins_list = plugins_list
  self.plugins_map = plugins_list_to_map(plugins_list)

  self.deflated_reconfigure_payload = nil
  self.reconfigure_payload = nil
  self.plugins_configured = {}
  self.plugin_versions = {}

  for i = 1, #plugins_list do
    local plugin = plugins_list[i]
    self.plugin_versions[plugin.name] = plugin.version
  end

  local push_config_semaphore = semaphore.new()

  -- When "clustering", "push_config" worker event is received by a worker,
  -- it loads and pushes the config to its the connected data planes
  kong.worker_events.register(function(_)
    if push_config_semaphore:count() <= 0 then
      -- the following line always executes immediately after the `if` check
      -- because `:count` will never yield, end result is that the semaphore
      -- count is guaranteed to not exceed 1
      push_config_semaphore:post()
    end
  end, "clustering", "push_config")

  timer_at(0, push_config_loop, self, push_config_semaphore,
               self.conf.db_update_frequency)
end


return _M
