-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local _M = {}


local semaphore = require("ngx.semaphore")
local ws_server = require("resty.websocket.server")
local cjson = require("cjson.safe")
local declarative = require("kong.db.declarative")
local utils = require("kong.tools.utils")
local constants = require("kong.constants")
local string = string
local assert = assert
local setmetatable = setmetatable
local type = type
local math = math
local pcall = pcall
local pairs = pairs
local tostring = tostring
local ngx = ngx
local ngx_log = ngx.log
local cjson_decode = cjson.decode
local cjson_encode = cjson.encode
local kong = kong
local ngx_exit = ngx.exit
local exiting = ngx.worker.exiting
local ngx_time = ngx.time
local ngx_now = ngx.now
local ngx_var = ngx.var
local table_insert = table.insert
local table_remove = table.remove
local deflate_gzip = utils.deflate_gzip


local kong_dict = ngx.shared.kong
local KONG_VERSION = kong.version
local ngx_ERR = ngx.ERR
local ngx_DEBUG = ngx.DEBUG
local ngx_WARN = ngx.WARN
local ngx_NOTICE = ngx.NOTICE
local ngx_OK = ngx.OK
local MAX_PAYLOAD = constants.CLUSTERING_MAX_PAYLOAD
local WS_OPTS = {
  timeout = constants.CLUSTERING_TIMEOUT,
  max_payload_len = MAX_PAYLOAD,
}
local PING_INTERVAL = constants.CLUSTERING_PING_INTERVAL
local PING_WAIT = PING_INTERVAL * 1.5
local CLUSTERING_SYNC_STATUS = constants.CLUSTERING_SYNC_STATUS


local function is_timeout(err)
  return err and string.sub(err, -7) == "timeout"
end


function _M.new(parent)
  local self = {
    clients = setmetatable({}, { __mode = "k", })
  }

  setmetatable(self, {
    __index = function(tab, key)
      return _M[key] or parent[key]
    end,
  })

  self.plugins_map = {}

  return self
end


function _M:export_deflated_reconfigure_payload()
  local config_table, err = declarative.export_config()
  if not config_table then
    return nil, err
  end

  -- reset plugins map
  for _, plugin_meta in pairs(self.plugins_map) do
    plugin_meta.included = 0
  end

  -- update plugins map
  if config_table.plugins then
    for _, plugin in pairs(config_table.plugins) do
      self.plugins_map[plugin.name].included = 1
    end
  end


  -- store serialized plugins map for troubleshooting purposes
  local shm_key_name = "clustering:cp_plugins_map:worker_" .. ngx.worker.id()
  kong_dict:set(shm_key_name, cjson_encode(self.plugins_map));

  ngx_log(ngx_DEBUG, "plugin configuration map key: " .. shm_key_name .. " configuration: ", kong_dict:get(shm_key_name))

  local payload, err = cjson_encode({
    type = "reconfigure",
    timestamp = ngx_now(),
    config_table = config_table,
  })
  if not payload then
    return nil, err
  end

  payload, err = deflate_gzip(payload)
  if not payload then
    return nil, err
  end

  self.deflated_reconfigure_payload = payload

  return payload
end


function _M:push_config()
  local payload, err = self:export_deflated_reconfigure_payload()
  if not payload then
    ngx_log(ngx_ERR, "unable to export config from database: " .. err)
    return
  end

  local n = 0
  for _, client in pairs(self.clients) do
    -- perform plugin compatibility check
    local res, err = self:should_send_config_update(client.node_version, client.node_plugins)
    if res then
      table_insert(client.queue, payload)
      client.queue.post()
      n = n + 1
    else
      ngx_log(ngx_WARN, "unable to send updated configuration to " ..
        "DP node with hostname: " .. client.node_hostname ..
        " ip: " .. client.node_ip ..
        " reason: " .. err)
    end
  end

  ngx_log(ngx_DEBUG, "config pushed to ", n, " clients")
end


local MAJOR_MINOR_PATTERN = "^(%d+)%.(%d+)%.%d+"

function _M:should_send_config_update(node_version, node_plugins)
  if not node_version or not node_plugins then
    return false, "your DP did not provide version information to the CP, " ..
                  "Kong CP after 2.3 requires such information in order to " ..
                  "ensure generated config is compatible with DPs. " ..
                  "Sync is suspended for this DP and will resume " ..
                  "automatically once this DP also upgrades to 2.3 or later"
  end

  local major_cp, minor_cp = KONG_VERSION:match(MAJOR_MINOR_PATTERN)
  local major_node, minor_node = node_version:match(MAJOR_MINOR_PATTERN)
  minor_cp = tonumber(minor_cp)
  minor_node = tonumber(minor_node)

  if major_cp ~= major_node or minor_cp - 2 > minor_node or minor_cp < minor_node then
    return false, "version incompatible, CP version: " .. KONG_VERSION ..
                  " DP version: " .. node_version ..
                  " DP versions acceptable are " ..
                  major_cp .. "." .. math.max(0, minor_cp - 2) .. " to " ..
                  major_cp .. "." .. minor_cp .. "(edges included)",
                  CLUSTERING_SYNC_STATUS.KONG_VERSION_INCOMPATIBLE
  end

  -- iterate over control plane plugins map
  for plugin_name, plugin_meta in pairs(self.plugins_map) do

    -- check plugin only if it is included in the current config export
    if plugin_meta.included == 1 then
      -- if plugin isn't enabled on the data plane node return immediately
      if not node_plugins[plugin_name] then
        return false, "CP and DP do not have same set of plugins installed, " ..
          "plugin: " .. tostring(plugin_name) .. " is missing",
                        CLUSTERING_SYNC_STATUS.PLUGIN_SET_INCOMPATIBLE
      end

      -- ignore plugins without a version (route-by-header is deprecated)
      if plugin_meta.version and node_plugins[plugin_name].version then
        local major_minor_p = plugin_meta.version:match("^(%d+%.%d+)") or "not_a_version"
        local major_minor_np = node_plugins[plugin_name].version:match("^(%d+%.%d+)") or "still_not_a_version"
        
        if major_minor_p ~= major_minor_np then
          return false, "plugin \"" .. plugin_name .. "\" version incompatible, " ..
            "CP version: " .. tostring(plugin_meta.version) ..
            " DP version: " .. tostring(node_plugins[plugin_name].version) ..
            " DP plugin version acceptable is "..
            major_minor_p .. ".x",
          CLUSTERING_SYNC_STATUS.PLUGIN_VERSION_INCOMPATIBLE
        end
      end
    end
  end

  return true
end


function _M:handle_cp_websocket()
  -- use mutual TLS authentication
  local ok, err = self:validate_client_cert(ngx_var.ssl_client_raw_cert)
  if not ok then
    ngx_log(ngx_ERR, err)
    return ngx_exit(444)
  end

  local node_id = ngx_var.arg_node_id
  if not node_id then
    ngx_exit(400)
  end

  local node_hostname = ngx_var.arg_node_hostname
  local node_ip = ngx_var.remote_addr
  local node_version = ngx_var.arg_node_version
  local node_plugins

  local wb, err = ws_server:new(WS_OPTS)
  if not wb then
    ngx_log(ngx_ERR, "failed to perform server side WebSocket handshake: ", err)
    return ngx_exit(444)
  end

  -- connection established
  -- receive basic_info
  local data, typ
  data, typ, err = wb:recv_frame()
  if err then
    ngx_log(ngx_ERR, "failed to receive WebSocket basic_info frame: ", err)
    wb:close()
    return ngx_exit(444)

  elseif typ == "binary" then
    data = cjson_decode(data)
    assert(data.type =="basic_info")
    node_plugins = assert(data.plugins)
  end

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

  local NODE_PLUGINS_MAP = {}
  for _, plugin in pairs(node_plugins) do
    NODE_PLUGINS_MAP[plugin.name] = { version = plugin.version }
  end

  self.clients[wb] = {
    queue = queue,
    node_hostname = node_hostname,
    node_ip = node_ip,
    node_version = node_version,
    node_plugins = NODE_PLUGINS_MAP
  }

  if not self.deflated_reconfigure_payload then
    assert(self:export_deflated_reconfigure_payload())
  end

  local res, sync_status
  res, err, sync_status = self:should_send_config_update(node_version, NODE_PLUGINS_MAP)
  if res then
    sync_status = CLUSTERING_SYNC_STATUS.NORMAL

    if self.deflated_reconfigure_payload then
      table_insert(queue, self.deflated_reconfigure_payload)
      queue.post()

    else
      ngx_log(ngx_ERR, "unable to export config from database: ".. err)
    end

  else
    ngx_log(ngx_WARN, "unable to send updated configuration to " ..
                      "DP node with hostname: " .. node_hostname ..
                      " ip: " .. node_ip ..
                      " reason: " .. err)
  end
  -- how CP connection management works:
  -- two threads are spawned, when any of these threads exits,
  -- it means a fatal error has occurred on the connection,
  -- and the other thread is also killed
  --
  -- * read_thread: it is the only thread that receives WS frames from the DP
  --                and records the current DP status in the database,
  --                and is also responsible for handling timeout detection
  -- * write_thread: it is the only thread that sends WS frames to the DP by
  --                 grabbing any messages currently in the send queue and
  --                 send them to the DP in a FIFO order. Notice that the
  --                 PONG frames are also sent by this thread after they are
  --                 queued by the read_thread

  local read_thread = ngx.thread.spawn(function()
    local last_seen = ngx_time()
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
          return
        end

        if not data then
          return nil, "did not receive ping frame from data plane"
        end

        -- dps only send pings
        if typ ~= "ping" then
          return nil, "invalid websocket frame received from a data plane: " .. typ
        end

        -- queue PONG to avoid races
        table_insert(queue, "PONG")
        queue.post()

        last_seen = ngx_time()

        local ok
        ok, err = kong.db.clustering_data_planes:upsert({ id = node_id, }, {
          last_seen = last_seen,
          config_hash = data ~= "" and data or nil,
          hostname = node_hostname,
          ip = node_ip,
          version = node_version,
          sync_status = sync_status,
        }, { ttl = self.conf.cluster_data_plane_purge_delay, })
        if not ok then
          ngx_log(ngx_ERR, "unable to update clustering data plane status: ", err)
        end
      end
    end
  end)

  local write_thread = ngx.thread.spawn(function()
    while not exiting() do
      local ok, err = queue.wait(5)
      if exiting() then
        return
      end
      if ok then
        local payload = table_remove(queue, 1)
        if not payload then
          return nil, "config queue can not be empty after semaphore returns"
        end

        if payload == "PONG" then
          local _, err = wb:send_pong()
          if err then
            if not is_timeout(err) then
              return nil, "failed to send PONG back to data plane: " .. err
            end

            ngx_log(ngx_NOTICE, "failed to send PONG back to data plane: ", err)

          else
            ngx_log(ngx_DEBUG, "sent PONG packet to data plane")
          end

        else
          ok, err = self:should_send_config_update(node_version, NODE_PLUGINS_MAP)
          if ok then
            -- config update
            local _, err = wb:send_binary(payload)
            if err then
              if not is_timeout(err) then
                return nil, "unable to send updated configuration to node: " .. err
              end

              ngx_log(ngx_NOTICE, "unable to send updated configuration to node: ", err)

            else
              ngx_log(ngx_DEBUG, "sent config update to node")
            end

          else
            ngx_log(ngx_WARN, "unable to send updated configuration to " ..
                              "DP node with hostname: " .. node_hostname ..
                              " ip: " .. node_ip ..
                              " reason: " .. err)
          end
        end

      elseif err ~= "timeout" then
        return nil, "semaphore wait error: " .. err
      end
    end
  end)

  local ok, err, perr = ngx.thread.wait(write_thread, read_thread)

  ngx.thread.kill(write_thread)
  ngx.thread.kill(read_thread)

  wb:send_close()

  if not ok then
    ngx_log(ngx_ERR, err)
    return ngx_exit(ngx_ERR)
  end

  if perr then
    ngx_log(ngx_ERR, perr)
    return ngx_exit(ngx_ERR)
  end

  return ngx_exit(ngx_OK)
end


local function push_config_loop(premature, self, push_config_semaphore, delay)
  if premature then
    return
  end

  local _, err = self:export_deflated_reconfigure_payload()
  if err then
    ngx_log(ngx_ERR, "unable to export initial config from database: " .. err)
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
        ngx_log(ngx_ERR, "export and pushing config failed: ", err)
      end

    elseif err ~= "timeout" then
      ngx_log(ngx_ERR, "semaphore wait error: ", err)
    end
  end
end


function _M:init_worker()
  -- ROLE = "control_plane"

  local push_config_semaphore = semaphore.new()

  for _, plugin in pairs(self.plugins_list) do
    self.plugins_map[plugin.name] = { version = plugin.version, included = 0 }
  end

  -- Sends "clustering", "push_config" to all workers in the same node, including self
  local function post_push_config_event()
    local res, err = kong.worker_events.post("clustering", "push_config")
    if not res then
      ngx_log(ngx_ERR, "unable to broadcast event: ", err)
    end
  end

  -- Handles "clustering:push_config" cluster event
  local function handle_clustering_push_config_event(data)
    ngx_log(ngx_DEBUG, "received clustering:push_config event for ", data)
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
  -- changes in the cache shared dict. Since DPs don't use the cache, nodes in the same
  -- kong node where the event originated will need to be notified so they push config to
  -- their DPs
  kong.worker_events.register(handle_dao_crud_event, "dao:crud")

  -- When "clustering", "push_config" worker event is received by a worker,
  -- it loads and pushes the config to its the connected DPs
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
