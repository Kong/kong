local _M = {}
local _MT = { __index = _M, }


local semaphore = require("ngx.semaphore")
local cjson = require("cjson.safe")
local declarative = require("kong.db.declarative")
local clustering_utils = require("kong.clustering.utils")
local compat = require("kong.clustering.compat")
local constants = require("kong.constants")
local events = require("kong.clustering.events")
local calculate_config_hash = require("kong.clustering.config_helper").calculate_config_hash


local string = string
local setmetatable = setmetatable
local type = type
local pcall = pcall
local pairs = pairs
local ngx = ngx
local ngx_log = ngx.log
local timer_at = ngx.timer.at
local cjson_decode = cjson.decode
local cjson_encode = cjson.encode
local kong = kong
local ngx_exit = ngx.exit
local exiting = ngx.worker.exiting
local worker_id = ngx.worker.id
local ngx_time = ngx.time
local ngx_now = ngx.now
local ngx_update_time = ngx.update_time
local ngx_var = ngx.var
local table_insert = table.insert
local table_remove = table.remove
local sub = string.sub
local isempty = require("table.isempty")
local sleep = ngx.sleep


local plugins_list_to_map = compat.plugins_list_to_map
local update_compatible_payload = compat.update_compatible_payload
local deflate_gzip = require("kong.tools.gzip").deflate_gzip
local yield = require("kong.tools.yield").yield
local connect_dp = clustering_utils.connect_dp


local kong_dict = ngx.shared.kong
local ngx_DEBUG = ngx.DEBUG
local ngx_NOTICE = ngx.NOTICE
local ngx_WARN = ngx.WARN
local ngx_ERR = ngx.ERR
local ngx_OK = ngx.OK
local ngx_ERROR = ngx.ERROR
local ngx_CLOSE = ngx.HTTP_CLOSE
local PING_WAIT = constants.CLUSTERING_PING_INTERVAL * 1.5
local CLUSTERING_SYNC_STATUS = constants.CLUSTERING_SYNC_STATUS
local DECLARATIVE_EMPTY_CONFIG_HASH = constants.DECLARATIVE_EMPTY_CONFIG_HASH
local PONG_TYPE = "PONG"
local RECONFIGURE_TYPE = "RECONFIGURE"
local _log_prefix = "[clustering] "


local no_connected_clients_logged


local function handle_export_deflated_reconfigure_payload(self)
  ngx_log(ngx_DEBUG, _log_prefix, "exporting config")

  local ok, p_err, err = pcall(self.export_deflated_reconfigure_payload, self)
  return ok, p_err or err
end


local function is_timeout(err)
  return err and sub(err, -7) == "timeout"
end


local function extract_dp_cert(cert)
  local expiry_timestamp = cert:get_not_after()
  -- values in cert_details must be strings
  local cert_details = {
    expiry_timestamp = expiry_timestamp,
  }

  return cert_details
end


function _M.new(clustering)
  assert(type(clustering) == "table",
         "kong.clustering is not instantiated")

  assert(type(clustering.conf) == "table",
         "kong.clustering did not provide configuration")

  local self = {
    clients = setmetatable({}, { __mode = "k", }),
    plugins_map = {},
    conf = clustering.conf,
  }

  return setmetatable(self, _MT)
end


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

  -- store serialized plugins map for troubleshooting purposes
  local shm_key_name = "clustering:cp_plugins_configured:worker_" .. (worker_id() or -1)
  kong_dict:set(shm_key_name, cjson_encode(self.plugins_configured))
  ngx_log(ngx_DEBUG, "plugin configuration map key: ", shm_key_name, " configuration: ", kong_dict:get(shm_key_name))

  local config_hash, hashes = calculate_config_hash(config_table)

  local payload = {
    type = "reconfigure",
    timestamp = ngx_now(),
    config_table = config_table,
    config_hash = config_hash,
    hashes = hashes,
  }

  self.reconfigure_payload = payload

  payload, err = cjson_encode(payload)
  if not payload then
    return nil, err
  end

  yield()

  payload, err = deflate_gzip(payload)
  if not payload then
    return nil, err
  end

  yield()

  self.current_hashes = hashes
  self.current_config_hash = config_hash
  self.deflated_reconfigure_payload = payload

  return payload, nil, config_hash
end


function _M:push_config()
  local start = ngx_now()

  local payload, err = self:export_deflated_reconfigure_payload()
  if not payload then
    ngx_log(ngx_ERR, _log_prefix, "unable to export config from database: ", err)
    return
  end

  local n = 0
  for _, queue in pairs(self.clients) do
    table_insert(queue, RECONFIGURE_TYPE)
    queue.post()
    n = n + 1
  end

  ngx_update_time()
  local duration = ngx_now() - start
  ngx_log(ngx_DEBUG, _log_prefix, "config pushed to ", n, " data-plane nodes in ", duration, " seconds")
end


_M.check_version_compatibility = compat.check_version_compatibility
_M.check_configuration_compatibility = compat.check_configuration_compatibility


function _M:handle_cp_websocket(cert)
  local dp_id = ngx_var.arg_node_id
  local dp_hostname = ngx_var.arg_node_hostname
  local dp_ip = ngx_var.remote_addr
  local dp_version = ngx_var.arg_node_version

  local wb, log_suffix, ec = connect_dp(dp_id, dp_hostname, dp_ip, dp_version)
  if not wb then
    return ngx_exit(ec)
  end

  -- connection established
  -- receive basic info
  local data, typ, err
  data, typ, err = wb:recv_frame()
  if err then
    err = "failed to receive websocket basic info frame: " .. err

  elseif typ == "binary" then
    if not data then
      err = "failed to receive websocket basic info data"

    else
      data, err = cjson_decode(data)
      if type(data) ~= "table" then
          err = "failed to decode websocket basic info data" ..
                (err and ": " .. err or "")

      else
        if data.type ~= "basic_info" then
          err = "invalid basic info data type: " .. (data.type or "unknown")

        else
          if type(data.plugins) ~= "table" then
            err = "missing plugins in basic info data"
          end
        end
      end
    end
  end

  if err then
    ngx_log(ngx_ERR, _log_prefix, err, log_suffix)
    wb:send_close()
    return ngx_exit(ngx_CLOSE)
  end

  local dp_cert_details = extract_dp_cert(cert)
  local dp_plugins_map = plugins_list_to_map(data.plugins)
  local config_hash = DECLARATIVE_EMPTY_CONFIG_HASH -- initial hash
  local last_seen = ngx_time()
  local sync_status = CLUSTERING_SYNC_STATUS.UNKNOWN
  local purge_delay = self.conf.cluster_data_plane_purge_delay
  local update_sync_status = function()
    local ok
    ok, err = kong.db.clustering_data_planes:upsert({ id = dp_id }, {
      last_seen = last_seen,
      config_hash = config_hash ~= ""
                and config_hash
                 or DECLARATIVE_EMPTY_CONFIG_HASH,
      hostname = dp_hostname,
      ip = dp_ip,
      version = dp_version,
      sync_status = sync_status, -- TODO: import may have been failed though
      labels = data.labels,
      cert_details = dp_cert_details,
    }, { ttl = purge_delay })
    if not ok then
      ngx_log(ngx_ERR, _log_prefix, "unable to update clustering data plane status: ", err, log_suffix)
    end
  end

  local _
  _, err, sync_status = self:check_version_compatibility({
    dp_version = dp_version,
    dp_plugins_map = dp_plugins_map,
    log_suffix = log_suffix,
  })
  if err then
    ngx_log(ngx_ERR, _log_prefix, err, log_suffix)
    wb:send_close()
    update_sync_status()
    return ngx_exit(ngx_CLOSE)
  end

  ngx_log(ngx_DEBUG, _log_prefix, "data plane connected", log_suffix)

  local queue
  do
    local queue_semaphore = semaphore.new()
    queue = {
      wait = function(...)
        return queue_semaphore:wait(...)
      end,
      post = function(...)
        return queue_semaphore:post(...)
      end
    }
  end

  -- if clients table is empty, we might have skipped some config
  -- push event in `push_config_loop`, which means the cached config
  -- might be stale, so we always export the latest config again in this case
  if isempty(self.clients) or not self.deflated_reconfigure_payload then
    _, err = handle_export_deflated_reconfigure_payload(self)
  end

  self.clients[wb] = queue

  if self.deflated_reconfigure_payload then
    -- initial configuration compatibility for sync status variable
    _, _, sync_status = self:check_configuration_compatibility({
      dp_plugins_map = dp_plugins_map,
      filters = data.filters,
    })

    table_insert(queue, RECONFIGURE_TYPE)
    queue.post()

  else
    ngx_log(ngx_ERR, _log_prefix, "unable to send initial configuration to data plane: ", err, log_suffix)
  end

  -- how control plane connection management works:
  -- two threads are spawned, when any of these threads exits,
  -- it means a fatal error has occurred on the connection,
  -- and the other thread is also killed
  --
  -- * read_thread: it is the only thread that receives websocket frames from the
  --                data plane and records the current data plane status in the
  --                database, and is also responsible for handling timeout detection
  -- * write_thread: it is the only thread that sends websocket frames to the data plane
  --                 by grabbing any messages currently in the send queue and
  --                 send them to the data plane in a FIFO order. Notice that the
  --                 PONG frames are also sent by this thread after they are
  --                 queued by the read_thread

  local read_thread = ngx.thread.spawn(function()
    while not exiting() do
      local data, typ, err = wb:recv_frame()

      if exiting() then
        return
      end

      if err then
        if not is_timeout(err) then
          return nil, err
        end

        local waited = ngx_time() - last_seen
        if waited > PING_WAIT then
          return nil, "did not receive ping frame from data plane within " ..
                      PING_WAIT .. " seconds"
        end

        -- timeout
        goto continue
      end

      if typ == "close" then
        ngx_log(ngx_DEBUG, _log_prefix, "received close frame from data plane", log_suffix)
        return
      end

      if not data then
        return nil, "did not receive ping frame from data plane"

      elseif #data ~= 32 then
        return nil, "received a ping frame from the data plane with an invalid"
                 .. " hash: '" .. tostring(data) .. "'"
      end

      -- dps only send pings
      if typ ~= "ping" then
        return nil, "invalid websocket frame received from data plane: " .. typ
      end

      ngx_log(ngx_DEBUG, _log_prefix, "received ping frame from data plane", log_suffix)

      config_hash = data
      last_seen = ngx_time()
      update_sync_status()

      -- queue PONG to avoid races
      table_insert(queue, PONG_TYPE)
      queue.post()

      ::continue::
    end
  end)

  local write_thread = ngx.thread.spawn(function()
    while not exiting() do
      local ok, err = queue.wait(5)

      if exiting() then
        return
      end

      if not ok then
        if err ~= "timeout" then
          return nil, "semaphore wait error: " .. err
        end

        -- timeout
        goto continue
      end

      local payload = table_remove(queue, 1)
      if not payload then
        return nil, "config queue can not be empty after semaphore returns"
      end

      if payload == PONG_TYPE then
        local _, err = wb:send_pong()
        if err then
          if not is_timeout(err) then
            return nil, "failed to send pong frame to data plane: " .. err
          end

          ngx_log(ngx_NOTICE, _log_prefix, "failed to send pong frame to data plane: ", err, log_suffix)

        else
          ngx_log(ngx_DEBUG, _log_prefix, "sent pong frame to data plane", log_suffix)
        end

        -- pong ok
        goto continue
      end

      -- is reconfigure
      assert(payload == RECONFIGURE_TYPE)

      local previous_sync_status = sync_status
      ok, err, sync_status = self:check_configuration_compatibility({
        dp_plugins_map = dp_plugins_map,
        filters = data.filters,
      })

      if not ok then
        ngx_log(ngx_WARN, _log_prefix, "unable to send updated configuration to data plane: ", err, log_suffix)
        if sync_status ~= previous_sync_status then
          update_sync_status()
        end

        goto continue
      end

      local _, deflated_payload, err = update_compatible_payload(self.reconfigure_payload, dp_version, log_suffix)

      if not deflated_payload then -- no modification or err, use the cached payload
        deflated_payload = self.deflated_reconfigure_payload
      end

      if err then
        ngx_log(ngx_WARN, "unable to update compatible payload: ", err, ", the unmodified config ",
                          "is returned", log_suffix)
      end

      -- config update
      local _, err = wb:send_binary(deflated_payload)
      if err then
        if not is_timeout(err) then
          return nil, "unable to send updated configuration to data plane: " .. err
        end

        ngx_log(ngx_NOTICE, _log_prefix, "unable to send updated configuration to data plane: ", err, log_suffix)

      else
        ngx_log(ngx_DEBUG, _log_prefix, "sent config update to data plane", log_suffix)
      end

      ::continue::
    end
  end)

  local ok, err, perr = ngx.thread.wait(write_thread, read_thread)

  self.clients[wb] = nil

  ngx.thread.kill(write_thread)
  ngx.thread.kill(read_thread)

  wb:send_close()

  --TODO: should we update disconnect data plane status?
  --sync_status = CLUSTERING_SYNC_STATUS.UNKNOWN
  --update_sync_status()

  if not ok then
    ngx_log(ngx_ERR, _log_prefix, err, log_suffix)
    return ngx_exit(ngx_ERROR)
  end

  if perr then
    ngx_log(ngx_ERR, _log_prefix, perr, log_suffix)
    return ngx_exit(ngx_ERROR)
  end

  return ngx_exit(ngx_OK)
end


local function push_config_loop(premature, self, push_config_semaphore, delay)
  if premature then
    return
  end

  local ok, err = handle_export_deflated_reconfigure_payload(self)
  if not ok then
    ngx_log(ngx_ERR, _log_prefix, "unable to export initial config from database: ", err)
  end

  while not exiting() do
    local ok, err = push_config_semaphore:wait(1)
    if exiting() then
      return
    end

    if not ok then
      if err ~= "timeout" then
        ngx_log(ngx_ERR, _log_prefix, "semaphore wait error: ", err)
      end

      goto continue
    end

    if isempty(self.clients) then
      if not no_connected_clients_logged then
        ngx_log(ngx_DEBUG, _log_prefix, "skipping config push (no connected clients)")
        no_connected_clients_logged = true
      end
      sleep(1)
      -- re-queue the task. wait until we have clients connected
      if push_config_semaphore:count() <= 0 then
        push_config_semaphore:post()
      end

      goto continue
    end

    no_connected_clients_logged = nil

    ok, err = pcall(self.push_config, self)
    if not ok then
      ngx_log(ngx_ERR, _log_prefix, "export and pushing config failed: ", err)
      goto continue
    end

    -- push_config ok, waiting for a while

    local sleep_left = delay
    while sleep_left > 0 do
      if sleep_left <= 1 then
        sleep(sleep_left)
        break
      end

      sleep(1)

      if exiting() then
        return
      end

      sleep_left = sleep_left - 1
    end

    ::continue::
  end
end


function _M:init_worker(basic_info)
  -- ROLE = "control_plane"
  local plugins_list = basic_info.plugins
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

  self.filters = basic_info.filters

  local push_config_semaphore = semaphore.new()

  -- When "clustering", "push_config" worker event is received by a worker,
  -- it loads and pushes the config to its the connected data planes
  events.clustering_push_config(function(_)
    if push_config_semaphore:count() <= 0 then
      -- the following line always executes immediately after the `if` check
      -- because `:count` will never yield, end result is that the semaphore
      -- count is guaranteed to not exceed 1
      push_config_semaphore:post()
    end
  end)

  timer_at(0, push_config_loop, self, push_config_semaphore,
               self.conf.db_update_frequency)
end


return _M
