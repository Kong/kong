local _M = {}


local semaphore = require("ngx.semaphore")
local ws_server = require("resty.websocket.server")
local ssl = require("ngx.ssl")
local ocsp = require("ngx.ocsp")
local http = require("resty.http")
local cjson = require("cjson.safe")
local declarative = require("kong.db.declarative")
local constants = require("kong.constants")
local openssl_x509 = require("resty.openssl.x509")
local wrpc = require("kong.tools.wrpc")
local string = string
local setmetatable = setmetatable
local type = type
local pcall = pcall
local pairs = pairs
local ipairs = ipairs
local tonumber = tonumber
local tostring = tostring
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

local kong_dict = ngx.shared.kong
local KONG_VERSION = kong.version
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
local OCSP_TIMEOUT = constants.CLUSTERING_OCSP_TIMEOUT
local CLUSTERING_SYNC_STATUS = constants.CLUSTERING_SYNC_STATUS
local MAJOR_MINOR_PATTERN = "^(%d+)%.(%d+)%.%d+"
local _log_prefix = "[clustering] "

local wrpc_config_service

local function get_config_service(self)
  if not wrpc_config_service then
    wrpc_config_service = wrpc.new_service()
    wrpc_config_service:add("kong.services.config.v1.config")
    wrpc_config_service:set_handler("ConfigService.PingCP", function(peer)
      local client = self.clients[peer.conn]
      if client then
        client.last_seen = ngx_time()
        ngx_log(ngx_INFO, _log_prefix, "received ping frame from data plane")
      end
    end)
    wrpc_config_service:set_handler("ConfigService.ReportBasicInfo", function(peer, data)
      local client = self.clients[peer.conn]
      if client then
        ngx_log(ngx_INFO, _log_prefix, "Received BasicInfo package from client: ", client.dp_id)
        client.basic_info = data
        client.basic_info_semaphore:post()
      end
    end)
  end

  return wrpc_config_service
end


local function extract_major_minor(version)
  if type(version) ~= "string" then
    return nil, nil
  end

  local major, minor = version:match(MAJOR_MINOR_PATTERN)
  if not major then
    return nil, nil
  end

  major = tonumber(major, 10)
  minor = tonumber(minor, 10)

  return major, minor
end


local function plugins_list_to_map(plugins_list)
  local versions = {}
  for _, plugin in ipairs(plugins_list) do
    local name = plugin.name
    local version = plugin.version
    local major, minor = extract_major_minor(plugin.version)

    if major and minor then
      versions[name] = {
        major   = major,
        minor   = minor,
        version = version,
      }

    else
      versions[name] = {}
    end
  end
  return versions
end


function _M.new(parent)
  local self = {
    clients = setmetatable({}, { __mode = "k", }),
    plugins_map = {},
  }

  return setmetatable(self, {
    __index = function(tab, key)
      return _M[key] or parent[key]
    end,
  })
end


local ngx_null = ngx.null
local function remove_nulls(tbl)
  for k,v in pairs(tbl) do
    if v == ngx_null then
      tbl[k] = nil
    elseif type(v) == "table" then
      tbl[k] = remove_nulls(v)
    end
  end
  return tbl
end

local config_version = 0

function _M:export_deflated_reconfigure_payload()
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

  config_version = config_version + 1

  -- store serialized plugins map for troubleshooting purposes
  local shm_key_name = "clustering:cp_plugins_configured:worker_" .. ngx.worker.id()
  kong_dict:set(shm_key_name, cjson_encode(self.plugins_configured));
  ngx_log(ngx_DEBUG, "plugin configuration map key: " .. shm_key_name .. " configuration: ", kong_dict:get(shm_key_name))

  local payload = remove_nulls({
    format_version = config_table._format_version,
    services = config_table.services,
    routes = config_table.routes,
    consumers = config_table.consumers,
    plugins = config_table.plugins,
    upstreams = config_table.upstreams,
    targets = config_table.targets,
    certificates = config_table.certificates,
    snis = config_table.snis,
    ca_certificates = config_table.ca_certificates,
    plugin_data = config_table.plugin_data,
    workspaces = config_table.workspaces,
  })
  for _, plugin in ipairs(payload.plugins) do
    plugin.config = wrpc.pbwrap_struct(plugin.config)
  end
  local service = get_config_service(self)
  self.config_call_rpc, self.config_call_args = assert(service:encode_args("ConfigService.SyncConfig", {
    config = payload,
    version = config_version,
  }))

  return payload, nil
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

  ngx_log(ngx_NOTICE, _log_prefix, "config version #", config_version, " pushed to ", n, " clients")
end


function _M:validate_shared_cert()
  local cert = ngx_var.ssl_client_raw_cert

  if not cert then
    return nil, "data plane failed to present client certificate during handshake"
  end

  local err
  cert, err = openssl_x509.new(cert, "PEM")
  if not cert then
    return nil, "unable to load data plane client certificate during handshake: " .. err
  end

  local digest
  digest, err = cert:digest("sha256")
  if not digest then
    return nil, "unable to retrieve data plane client certificate digest during handshake: " .. err
  end

  if digest ~= self.cert_digest then
    return nil, "data plane presented incorrect client certificate during handshake (expected: " ..
                self.cert_digest .. ", got: " .. digest .. ")"
  end

  return true
end


local check_for_revocation_status
do
  local get_full_client_certificate_chain = require("resty.kong.tls").get_full_client_certificate_chain
  check_for_revocation_status = function()
    local cert, err = get_full_client_certificate_chain()
    if not cert then
      return nil, err
    end

    local der_cert
    der_cert, err = ssl.cert_pem_to_der(cert)
    if not der_cert then
      return nil, "failed to convert certificate chain from PEM to DER: " .. err
    end

    local ocsp_url
    ocsp_url, err = ocsp.get_ocsp_responder_from_der_chain(der_cert)
    if not ocsp_url then
      return nil, err or "OCSP responder endpoint can not be determined, " ..
                         "maybe the client certificate is missing the " ..
                         "required extensions"
    end

    local ocsp_req
    ocsp_req, err = ocsp.create_ocsp_request(der_cert)
    if not ocsp_req then
      return nil, "failed to create OCSP request: " .. err
    end

    local c = http.new()
    local res
    res, err = c:request_uri(ocsp_url, {
      headers = {
        ["Content-Type"] = "application/ocsp-request"
      },
      timeout = OCSP_TIMEOUT,
      method = "POST",
      body = ocsp_req,
    })

    if not res then
      return nil, "failed sending request to OCSP responder: " .. tostring(err)
    end
    if res.status ~= 200 then
      return nil, "OCSP responder returns bad HTTP status code: " .. res.status
    end

    local ocsp_resp = res.body
    if not ocsp_resp or #ocsp_resp == 0 then
      return nil, "unexpected response from OCSP responder: empty body"
    end

    res, err = ocsp.validate_ocsp_response(ocsp_resp, der_cert)
    if not res then
      return false, "failed to validate OCSP response: " .. err
    end

    return true
  end
end


function _M:check_version_compatibility(dp_version, dp_plugin_map, log_suffix)
  local major_cp, minor_cp = extract_major_minor(KONG_VERSION)
  local major_dp, minor_dp = extract_major_minor(dp_version)

  if not major_cp then
    return nil, "data plane version " .. dp_version .. " is incompatible with control plane version",
                CLUSTERING_SYNC_STATUS.KONG_VERSION_INCOMPATIBLE
  end

  if not major_dp then
    return nil, "data plane version is incompatible with control plane version " ..
                KONG_VERSION .. " (" .. major_cp .. ".x.y are accepted)",
                CLUSTERING_SYNC_STATUS.KONG_VERSION_INCOMPATIBLE
  end

  if major_cp ~= major_dp then
    return nil, "data plane version " .. dp_version ..
                " is incompatible with control plane version " ..
                KONG_VERSION .. " (" .. major_cp .. ".x.y are accepted)",
                CLUSTERING_SYNC_STATUS.KONG_VERSION_INCOMPATIBLE
  end

  if minor_cp < minor_dp then
    return nil, "data plane version " .. dp_version ..
                " is incompatible with older control plane version " .. KONG_VERSION,
                CLUSTERING_SYNC_STATUS.KONG_VERSION_INCOMPATIBLE
  end

  if minor_cp ~= minor_dp then
    local msg = "data plane minor version " .. dp_version ..
                " is different to control plane minor version " ..
                KONG_VERSION

    ngx_log(ngx_INFO, _log_prefix, msg, log_suffix)
  end

  for _, plugin in ipairs(self.plugins_list) do
    local name = plugin.name
    local cp_plugin = self.plugins_map[name]
    local dp_plugin = dp_plugin_map[name]

    if not dp_plugin then
      if cp_plugin.version then
        ngx_log(ngx_WARN, _log_prefix, name, " plugin ", cp_plugin.version, " is missing from data plane", log_suffix)
      else
        ngx_log(ngx_WARN, _log_prefix, name, " plugin is missing from data plane", log_suffix)
      end

    else
      if cp_plugin.version and dp_plugin.version then
        local msg = "data plane " .. name .. " plugin version " .. dp_plugin.version ..
                    " is different to control plane plugin version " .. cp_plugin.version

        if cp_plugin.major ~= dp_plugin.major then
          ngx_log(ngx_WARN, _log_prefix, msg, log_suffix)

        elseif cp_plugin.minor ~= dp_plugin.minor then
          ngx_log(ngx_INFO, _log_prefix, msg, log_suffix)
        end

      elseif dp_plugin.version then
        ngx_log(ngx_NOTICE, _log_prefix, "data plane ", name, " plugin version ", dp_plugin.version,
                        " has unspecified version on control plane", log_suffix)

      elseif cp_plugin.version then
        ngx_log(ngx_NOTICE, _log_prefix, "data plane ", name, " plugin version is unspecified, ",
                        "and is different to control plane plugin version ",
                        cp_plugin.version, log_suffix)
      end
    end
  end

  return true, nil, CLUSTERING_SYNC_STATUS.NORMAL
end


function _M:check_configuration_compatibility(dp_plugin_map)
  for _, plugin in ipairs(self.plugins_list) do
    if self.plugins_configured[plugin.name] then
      local name = plugin.name
      local cp_plugin = self.plugins_map[name]
      local dp_plugin = dp_plugin_map[name]

      if not dp_plugin then
        if cp_plugin.version then
          return nil, "configured " .. name .. " plugin " .. cp_plugin.version ..
                      " is missing from data plane", CLUSTERING_SYNC_STATUS.PLUGIN_SET_INCOMPATIBLE
        end

        return nil, "configured " .. name .. " plugin is missing from data plane",
               CLUSTERING_SYNC_STATUS.PLUGIN_SET_INCOMPATIBLE
      end

      if cp_plugin.version and dp_plugin.version then
        -- CP plugin needs to match DP plugins with major version
        -- CP must have plugin with equal or newer version than that on DP
        if cp_plugin.major ~= dp_plugin.major or
          cp_plugin.minor < dp_plugin.minor then
          local msg = "configured data plane " .. name .. " plugin version " .. dp_plugin.version ..
                      " is different to control plane plugin version " .. cp_plugin.version
          return nil, msg, CLUSTERING_SYNC_STATUS.PLUGIN_VERSION_INCOMPATIBLE
        end
      end
    end
  end

  -- TODO: DAOs are not checked in any way at the moment. For example if plugin introduces a new DAO in
  --       minor release and it has entities, that will most likely fail on data plane side, but is not
  --       checked here.

  return true, nil, CLUSTERING_SYNC_STATUS.NORMAL
end

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
    local _, err

    -- use mutual TLS authentication
    if self.conf.cluster_mtls == "shared" then
      _, err = self:validate_shared_cert()

    elseif self.conf.cluster_ocsp ~= "off" then
      local ok
      ok, err = check_for_revocation_status()
      if ok == false then
        err = "data plane client certificate was revoked: " ..  err

      elseif not ok then
        if self.conf.cluster_ocsp == "on" then
          err = "data plane client certificate revocation check failed: " .. err

        else
          ngx_log(ngx_WARN, _log_prefix, "data plane client certificate revocation check failed: ", err, log_suffix)
          err = nil
        end
      end
    end

    if err then
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
  client.update_sync_status = function()
    local ok, err = kong.db.clustering_data_planes:upsert({ id = dp_id, }, {
      last_seen = client.last_seen,
      config_hash = client.config_hash ~= "" and client.config_hash or nil,
      hostname = dp_hostname,
      ip = dp_ip,
      version = dp_version,
      sync_status = client.sync_status, -- TODO: import may have been failed though
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
      client.update_sync_status()
      return ngx_exit(ngx_CLOSE)
    end
  end

  self:push_config()    -- first config push

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
    local _, err = self:export_deflated_reconfigure_payload()
    if err then
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


function _M:init_worker()
  -- ROLE = "control_plane"

  self.plugins_map = plugins_list_to_map(self.plugins_list)

  self.deflated_reconfigure_payload = nil
  self.reconfigure_payload = nil
  self.plugins_configured = {}
  self.plugin_versions = {}

  for i = 1, #self.plugins_list do
    local plugin = self.plugins_list[i]
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
