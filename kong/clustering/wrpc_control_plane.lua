local _M = {}
local _MT = { __index = _M, }


local semaphore = require("ngx.semaphore")
local ws_server = require("resty.websocket.server")
local cjson = require("cjson.safe")
local declarative = require("kong.db.declarative")
local constants = require("kong.constants")
local clustering_utils = require("kong.clustering.utils")
local wrpc = require("kong.tools.wrpc")
local string = string
local setmetatable = setmetatable
local type = type
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
local table_insert = table.insert
local table_concat = table.concat

local calculate_config_hash = require("kong.clustering.config_helper").calculate_config_hash
local plugins_list_to_map = clustering_utils.plugins_list_to_map

local kong_dict = ngx.shared.kong
local ngx_DEBUG = ngx.DEBUG
local ngx_INFO = ngx.INFO
local ngx_NOTICE = ngx.NOTICE
local ngx_WARN = ngx.WARN
local ngx_ERR = ngx.ERR
local ngx_CLOSE = ngx.HTTP_CLOSE
local MAX_PAYLOAD = constants.CLUSTERING_MAX_PAYLOAD
local WS_OPTS = {
  timeout = constants.CLUSTERING_TIMEOUT,
  max_payload_len = MAX_PAYLOAD,
}
local CLUSTERING_SYNC_STATUS = constants.CLUSTERING_SYNC_STATUS
local _log_prefix = "[wrpc-clustering] "

local wrpc_config_service


local function handle_export_deflated_reconfigure_payload(self)
  local ok, p_err, err = pcall(self.export_deflated_reconfigure_payload, self)
  return ok, p_err or err
end


local function get_config_service(self)
  if not wrpc_config_service then
    wrpc_config_service = wrpc.new_service()
    wrpc_config_service:add("kong.services.config.v1.config")

    wrpc_config_service:set_handler("ConfigService.PingCP", function(peer, data)
      local client = self.clients[peer.conn]
      if client and client.update_sync_status then
        client.last_seen = ngx_time()
        client.config_hash = data.hash
        client:update_sync_status()
        ngx_log(ngx_INFO, _log_prefix, "received ping frame from data plane")
      end
    end)

    wrpc_config_service:set_handler("ConfigService.ReportMetadata", function(peer, data)
      local client = self.clients[peer.conn]
      if client then
        ngx_log(ngx_INFO, _log_prefix, "received initial metadata package from client: ", client.dp_id)
        client.basic_info = data
        client.basic_info_semaphore:post()
      end
      return {
        ok = "done",
      }
    end)
  end

  return wrpc_config_service
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
  local config_table, err = declarative.export_config_proto()
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
  kong_dict:set(shm_key_name, cjson_encode(self.plugins_configured));

  local service = get_config_service(self)
  self.config_call_rpc, self.config_call_args = assert(service:encode_args("ConfigService.SyncConfig", {
    config = config_table,
    version = config_version,
    config_hash = config_hash,
    hashes = hashes,
  }))

  return config_table, nil
end

function _M:push_config_one_client(client)
  if not self.config_call_rpc or not self.config_call_args then
    local ok, err = handle_export_deflated_reconfigure_payload(self)
    if not ok then
      ngx_log(ngx_ERR, _log_prefix, "unable to export config from database: ", err)
      return
    end
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
    client.peer:send_encoded_call(self.config_call_rpc, self.config_call_args)

    n = n + 1
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

  local log_suffix = {}
  if type(dp_id) == "string" then
    table_insert(log_suffix, "id: " .. dp_id)
  end

  if type(dp_hostname) == "string" then
    table_insert(log_suffix, "host: " .. dp_hostname)
  end

  if type(dp_ip) == "string" then
    table_insert(log_suffix, "ip: " .. dp_ip)
  end

  if type(dp_version) == "string" then
    table_insert(log_suffix, "version: " .. dp_version)
  end

  if #log_suffix > 0 then
    log_suffix = " [" .. table_concat(log_suffix, ", ") .. "]"
  else
    log_suffix = ""
  end

  do
    local ok, err = clustering_utils.validate_connection_certs(self.conf, self.cert_digest)
    if not ok then
      ngx_log(ngx_ERR, _log_prefix, err, log_suffix)
      return ngx_exit(ngx_CLOSE)
    end
  end

  if not dp_id then
    ngx_log(ngx_WARN, _log_prefix, "data plane didn't pass the id", log_suffix)
    ngx_exit(400)
  end

  if not dp_version then
    ngx_log(ngx_WARN, _log_prefix, "data plane didn't pass the version", log_suffix)
    ngx_exit(400)
  end

  local wb
  do
    local err
    wb, err = ws_server:new(WS_OPTS)
    if not wb then
      ngx_log(ngx_ERR, _log_prefix, "failed to perform server side websocket handshake: ", err, log_suffix)
      return ngx_exit(ngx_CLOSE)
    end
  end

  -- connection established
  local w_peer = wrpc.new_peer(wb, get_config_service(self))
  local client = {
    last_seen = ngx_time(),
    peer = w_peer,
    dp_id = dp_id,
    dp_version = dp_version,
    log_suffix = log_suffix,
    basic_info = nil,
    basic_info_semaphore = semaphore.new()
  }
  self.clients[w_peer.conn] = client
  w_peer:spawn_threads()

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

  client.dp_plugins_map = plugins_list_to_map(client.basic_info.plugins)
  client.config_hash = string.rep("0", 32) -- initial hash
  client.sync_status = CLUSTERING_SYNC_STATUS.UNKNOWN
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
    local _, err
    _, err, client.sync_status = self:check_version_compatibility(dp_version, client.dp_plugins_map, log_suffix)
    if err then
      ngx_log(ngx_ERR, _log_prefix, err, log_suffix)
      wb:send_close()
      client:update_sync_status()
      return ngx_exit(ngx_CLOSE)
    end
  end

  self:push_config_one_client(client)    -- first config push

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

    elseif err ~= "timeout" then
      ngx_log(ngx_ERR, _log_prefix, "semaphore wait error: ", err)
    end
  end
end


function _M:init_worker(plugins_list)
  -- ROLE = "control_plane"

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

  -- Sends "clustering", "push_config" to all workers in the same node, including self
  local function post_push_config_event()
    local res, err = kong.worker_events.post("clustering", "push_config")
    if not res then
      ngx_log(ngx_ERR, _log_prefix, "unable to broadcast event: ", err)
    end
  end

  -- Handles "clustering:push_config" cluster event
  local function handle_clustering_push_config_event(data)
    ngx_log(ngx_DEBUG, _log_prefix, "received clustering:push_config event for ", data)
    post_push_config_event()
  end


  -- Handles "dao:crud" worker event and broadcasts "clustering:push_config" cluster event
  local function handle_dao_crud_event(data)
    if type(data) ~= "table" or data.schema == nil or data.schema.db_export == false then
      return
    end

    kong.cluster_events:broadcast("clustering:push_config", data.schema.name .. ":" .. data.operation)

    -- we have to re-broadcast event using `post` because the dao
    -- events were sent using `post_local` which means not all workers
    -- can receive it
    post_push_config_event()
  end

  -- The "clustering:push_config" cluster event gets inserted in the cluster when there's
  -- a crud change (like an insertion or deletion). Only one worker per kong node receives
  -- this callback. This makes such node post push_config events to all the cp workers on
  -- its node
  kong.cluster_events:subscribe("clustering:push_config", handle_clustering_push_config_event)

  -- The "dao:crud" event is triggered using post_local, which eventually generates an
  -- ""clustering:push_config" cluster event. It is assumed that the workers in the
  -- same node where the dao:crud event originated will "know" about the update mostly via
  -- changes in the cache shared dict. Since data planes don't use the cache, nodes in the same
  -- kong node where the event originated will need to be notified so they push config to
  -- their data planes
  kong.worker_events.register(handle_dao_crud_event, "dao:crud")

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

  ngx.timer.at(0, push_config_loop, self, push_config_semaphore,
               self.conf.db_update_frequency)
end


return _M
