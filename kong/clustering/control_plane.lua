local _M = {}
local _MT = { __index = _M, }


local semaphore = require("ngx.semaphore")
local cjson = require("cjson.safe")
local compat = require("kong.clustering.compat")
local constants = require("kong.constants")


local export = require("kong.db.declarative.export").export
local calculate_config_hash = require("kong.clustering.config_helper").calculate_config_hash
local send_configuration_payload = require("kong.clustering.protocol").send_configuration_payload
local get_updated_monotonic_ms = require("kong.tools.utils").get_updated_monotonic_ms


local assert = assert
local setmetatable = setmetatable
local type = type
local pcall = pcall
local pairs = pairs
local ngx = ngx
local tostring = tostring
local timer_at = ngx.timer.at
local cjson_decode = cjson.decode
local cjson_encode = cjson.encode
local kong = kong
local ngx_exit = ngx.exit
local exiting = ngx.worker.exiting
local worker_id = ngx.worker.id
local ngx_time = ngx.time
local ngx_var = ngx.var
local table_insert = table.insert
local table_remove = table.remove
local isempty = require("table.isempty")
local sleep = ngx.sleep


local plugins_list_to_map = compat.plugins_list_to_map
local update_compatible_payload = compat.update_compatible_payload


local KONG_DICT = ngx.shared.kong
local PING_WAIT = constants.CLUSTERING_PING_INTERVAL * 1.5
local CLUSTERING_SYNC_STATUS = constants.CLUSTERING_SYNC_STATUS
local DECLARATIVE_EMPTY_CONFIG_HASH = constants.DECLARATIVE_EMPTY_CONFIG_HASH
local PONG_TYPE = "PONG"
local RECONFIGURE_TYPE = "RECONFIGURE"
local LOG_PREFIX = "[clustering] "


local no_connected_clients_logged


local function handle_export_reconfigure_payload(self)
  ngx.log(ngx.DEBUG, LOG_PREFIX, "exporting config")
  local ok, p_err, err = pcall(self.export_reconfigure_payload, self)
  return ok, p_err or err
end


local function is_timeout(err)
  return err and err:sub(-7) == "timeout"
end


function _M.new(clustering)
  assert(type(clustering) == "table", "kong.clustering is not instantiated")
  assert(type(clustering.conf) == "table", "kong.clustering did not provide configuration")

  local self = {
    clients = setmetatable({}, { __mode = "k", }),
    plugins_map = {},
    conf = clustering.conf,
  }

  return setmetatable(self, _MT)
end


function _M:export_reconfigure_payload()
  local start = get_updated_monotonic_ms()
  local config, err, plugins_configured = export()
  if not config then
    return nil, err
  end
  ngx.log(ngx.DEBUG, LOG_PREFIX, "configuration export took: ", get_updated_monotonic_ms() - start, " ms")

  -- store serialized plugins map for troubleshooting purposes
  local shm_key_name = "clustering:cp_plugins_configured:worker_" .. worker_id()
  KONG_DICT:set(shm_key_name, cjson_encode(plugins_configured))
  ngx.log(ngx.DEBUG, LOG_PREFIX, "plugin configuration map key: " .. shm_key_name .. " configuration: ", KONG_DICT:get(shm_key_name))

  start = get_updated_monotonic_ms()
  local _, hashes = calculate_config_hash(config)
  ngx.log(ngx.DEBUG, LOG_PREFIX, "configuration hash calculation took: ", get_updated_monotonic_ms() - start, " ms")

  self.plugins_configured = plugins_configured
  self.reconfigure_payload = {
    timestamp = get_updated_monotonic_ms(),
    config = config,
    hashes = hashes,
  }

  return true
end


function _M:push_config()
  local start = get_updated_monotonic_ms()

  local ok, err = self:export_reconfigure_payload()
  if not ok then
    ngx.log(ngx.ERR, LOG_PREFIX, "unable to export config from database: ", err)
    return
  end

  local n = 0
  for _, queue in pairs(self.clients) do
    table_insert(queue, RECONFIGURE_TYPE)
    queue.post()
    n = n + 1
  end

  local duration = get_updated_monotonic_ms() - start
  ngx.log(ngx.INFO, LOG_PREFIX, "config pushed to ", n, " data plane nodes in " .. duration .. " ms")
end


_M.check_version_compatibility = compat.check_version_compatibility
_M.check_configuration_compatibility = compat.check_configuration_compatibility


function _M:handle_cp_websocket()
  local dp_id = ngx_var.arg_node_id
  local dp_hostname = ngx_var.arg_node_hostname
  local dp_ip = ngx_var.remote_addr
  local dp_version = ngx_var.arg_node_version

  local wb, log_suffix, ec = require("kong.clustering.utils").connect_dp(dp_id, dp_hostname, dp_ip, dp_version)
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
    ngx.log(ngx.ERR, LOG_PREFIX, err, log_suffix)
    wb:send_close()
    return ngx_exit(ngx.HTTP_CLOSE)
  end

  local dp_plugins_map = plugins_list_to_map(data.plugins)

  local dp = {
    dp_hostname      = dp_hostname,
    dp_id            = dp_id,
    dp_plugins_map   = dp_plugins_map,
    dp_version       = dp_version,
    log_suffix       = log_suffix,
    filters          = data.filters,
  }

  local config_hash = DECLARATIVE_EMPTY_CONFIG_HASH -- initial hash
  local last_seen = ngx_time()
  local sync_status = CLUSTERING_SYNC_STATUS.UNKNOWN
  local purge_delay = self.conf.cluster_data_plane_purge_delay
  local update_sync_status = function()
    local ok
    ok, err = kong.db.clustering_data_planes:upsert({ id = dp_id, }, {
      last_seen = last_seen,
      config_hash = config_hash ~= ""
                and config_hash
                 or DECLARATIVE_EMPTY_CONFIG_HASH,
      hostname = dp_hostname,
      ip = dp_ip,
      version = dp_version,
      sync_status = sync_status, -- TODO: import may have been failed though
      labels = data.labels,
    }, { ttl = purge_delay })
    if not ok then
      ngx.log(ngx.ERR, LOG_PREFIX, "unable to update clustering data plane status: ", err, log_suffix)
    end
  end

  local _
  _, err, sync_status = self:check_version_compatibility(dp)
  if err then
    ngx.log(ngx.ERR, LOG_PREFIX, err, log_suffix)
    wb:send_close()
    update_sync_status()
    return ngx_exit(ngx.HTTP_CLOSE)
  end

  ngx.log(ngx.DEBUG, LOG_PREFIX, "data plane connected", log_suffix)

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
  if isempty(self.clients) or not self.reconfigure_payload then
    _, err = handle_export_reconfigure_payload(self)
  end

  self.clients[wb] = queue

  local send_first_payload = true

  if not self.reconfigure_payload then
    send_first_payload = false

  else
    -- initial configuration compatibility for sync status variable
    local ok
    ok, err, sync_status = self:check_configuration_compatibility(dp, self.reconfigure_payload.config)
    if not ok then
      update_sync_status()
    end
  end

  if send_first_payload then
    table_insert(queue, RECONFIGURE_TYPE)
    queue.post()

  else
    ngx.log(ngx.ERR, LOG_PREFIX, "unable to send initial configuration to data plane: ", err, log_suffix)
  end

  -- How control plane connection management works:
  --
  -- Two threads are spawned, when any of these threads exits,
  -- it means a fatal error has occurred on the connection,
  -- and the other thread is also killed
  --
  -- * read_thread:  it is the only thread that receives websocket frames from the
  --                 data plane and records the current data plane status in the
  --                 database, and is also responsible for handling timeout detection
  --
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

      else
        if typ == "close" then
          ngx.log(ngx.DEBUG, LOG_PREFIX, "received close frame from data plane", log_suffix)
          return
        end

      if not data then
        return nil, "did not receive ping frame from data plane"

      elseif #data ~= 32 then
        return nil, "received a ping frame from the data plane with an invalid"
                 .. " hash: '" .. tostring(data) .. "'"
      end

        if typ ~= "ping" then
          return nil, "invalid websocket frame received from data plane: " .. typ
        end

        ngx.log(ngx.DEBUG, LOG_PREFIX, "received ping frame from data plane", log_suffix)

        config_hash = data
        last_seen = ngx_time()
        update_sync_status()

        -- queue PONG to avoid races
        table_insert(queue, PONG_TYPE)
        queue.post()

        sleep(0)
      end
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

      else
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

            ngx.log(ngx.NOTICE, LOG_PREFIX, "failed to send pong frame to data plane: ", err, log_suffix)

          else
            ngx.log(ngx.DEBUG, LOG_PREFIX, "sent pong frame to data plane", log_suffix)
          end

        else
          assert(payload == RECONFIGURE_TYPE)

          local previous_sync_status = sync_status
          ok, err, sync_status = self:check_configuration_compatibility(dp)
          if not ok then
            ngx.log(ngx.WARN, LOG_PREFIX, "unable to send updated configuration to data plane: ", err, log_suffix)
            if sync_status ~= previous_sync_status then
              update_sync_status()
            end

          else
            local payload = assert(update_compatible_payload(self.reconfigure_payload, dp_version, log_suffix))
            send_configuration_payload(wb, payload)
          end
        end

        sleep(0)
      end
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

  local err_msg = ok and err or perr
  if err_msg then
    if err_msg:sub(-8) == ": closed" then
      ngx.log(ngx.INFO, LOG_PREFIX, "connection to data plane closed", log_suffix)
    else
      ngx.log(ngx.ERR, LOG_PREFIX, err_msg, log_suffix)
    end
    return ngx_exit(ngx.ERROR)
  end


  return ngx_exit(ngx.OK)
end


local function push_config_loop(premature, self, push_config_semaphore, delay)
  if premature then
    return
  end

  while not exiting() do
    local ok, err = push_config_semaphore:wait(1)
    if exiting() then
      return
    end

    if not ok then
      if err ~= "timeout" then
        ngx.log(ngx.ERR, LOG_PREFIX, "semaphore wait error: ", err)
      end

    else
      if isempty(self.clients) then
        if not no_connected_clients_logged then
          ngx.log(ngx.DEBUG, LOG_PREFIX, "skipping config push (no connected clients)")
          no_connected_clients_logged = true
        end

        sleep(1)

        -- re-queue the task. wait until we have clients connected
        if push_config_semaphore:count() <= 0 then
          push_config_semaphore:post()
        end

        sleep(0)

      else
        no_connected_clients_logged = nil

        ok, err = pcall(self.push_config, self)
        if not ok then
          ngx.log(ngx.ERR, LOG_PREFIX, "export and pushing config failed: ", err)
          sleep(0)

        else
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
        end
      end
    end
  end
end


function _M:init_worker(basic_info)
  -- ROLE = "control_plane"
  local plugins_list = basic_info.plugins
  self.plugins_list = plugins_list
  self.plugins_map = plugins_list_to_map(plugins_list)

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
  require("kong.clustering.events").clustering_push_config(function(_)
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
