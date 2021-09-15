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
local setmetatable = setmetatable
local type = type
local pcall = pcall
local pairs = pairs
local ipairs = ipairs
local tonumber = tonumber
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
local table_concat = table.concat
local gsub = string.gsub
local deflate_gzip = utils.deflate_gzip


local kong_dict = ngx.shared.kong
local KONG_VERSION = kong.version
local ngx_DEBUG = ngx.DEBUG
local ngx_INFO = ngx.INFO
local ngx_NOTICE = ngx.NOTICE
local ngx_WARN = ngx.WARN
local ngx_ERR = ngx.ERR
local ngx_OK = ngx.OK
local ngx_CLOSE = ngx.HTTP_CLOSE
local MAX_PAYLOAD = constants.CLUSTERING_MAX_PAYLOAD
local WS_OPTS = {
  timeout = constants.CLUSTERING_TIMEOUT,
  max_payload_len = MAX_PAYLOAD,
}
local PING_INTERVAL = constants.CLUSTERING_PING_INTERVAL
local PING_WAIT = PING_INTERVAL * 1.5
local CLUSTERING_SYNC_STATUS = constants.CLUSTERING_SYNC_STATUS
local PONG_TYPE = "PONG"
local RECONFIGURE_TYPE = "RECONFIGURE"
local MAJOR_MINOR_PATTERN = "^(%d+)%.(%d+)%.%d+"
local REMOVED_FIELDS = require("kong.clustering.compat.removed_fields")
local _log_prefix = "[clustering] "


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


local function is_timeout(err)
  return err and string.sub(err, -7) == "timeout"
end


function _M.new(parent)
  local self = {
    clients = setmetatable({}, { __mode = "k", }),
    plugins_map = {},
  }

  setmetatable(self, {
    __index = function(tab, key)
      return _M[key] or parent[key]
    end,
  })

  self.plugins_map = {}

  return self
end

-- [[ XXX EE:
--   - Handle redis timeout changes and syslog fields added in 2.5.0.0
--   - Handle log, prometheus, and zipkin fields added in 2.4.1.0
local gsub = string.gsub
local inflate_gzip = utils.inflate_gzip
local ENTERPRISE_VERSION_PATTERN = "^(%d+)%.(%d+)%.(%d+)%.(%d+)"

local function extract_enterprise_version(version)
  if type(version) ~= "string" then
    return 0, 0, 0, 0
  end

  local major, minor, patch, ent_patch = version:match(ENTERPRISE_VERSION_PATTERN)
  major = major and tonumber(major, 10) or 0
  minor = minor and tonumber(minor, 10) or 0
  patch = patch and tonumber(patch, 10) or 0
  ent_patch = ent_patch and tonumber(ent_patch, 10) or 0

  return major, minor, patch, ent_patch
end

local function invalidate_keys_from_config(config_plugins, keys)
  for _, t in ipairs(config_plugins) do
    if t and t["config"] then
      local config = t["config"]
      local name = gsub(t["name"], "-", "_")

      -- Handle Redis configurations (regardless of plugin)
      if config.redis then
        local config_plugin_redis = t["config"].redis
        for _, key in ipairs(keys["redis"]) do
          if config_plugin_redis[key] ~= nil then
            config_plugin_redis[key] = nil
          end
        end
      end

      -- Handle fields in specific plugins
      if keys[name] ~= nil then
        for _, key in ipairs(keys[name]) do
          if config[key] ~= nil then
            config[key] = nil
          end
        end
      end
    end
  end
end

local function dp_version_num()
  local dp_version = ngx_var.arg_node_version
  local major_dp, minor_dp, patch_dp, ent_patch_dp = extract_enterprise_version(dp_version)
  return (major_dp * 1000000000) +
         (minor_dp * 1000000) +
         (patch_dp * 1000) +
         ent_patch_dp
end

local function is_older_dataplane()
  local dp_version_num = dp_version_num()

  --[[
  -- Kong Gateway v2.3.3.3 and v2.4.1.2 will be backporting the clustering
  -- relaxation
  --]]
  return (dp_version_num > 2003000000 --[[ 2.3.0.0 ]] and dp_version_num < 2003003003) --[[ 2.3.3.3 ]]
         or (dp_version_num > 2004000000 --[[ 2.4.0.0 ]] and dp_version_num < 2004001002) --[[ 2.4.1.2 ]]
         or dp_version_num <= 2003000000 --[[ 2.3.0.0; everything else that came before ]]

end

local function handle_config_removal(config_table)
  local fields_2003003003 = {
    file_log = {
      "custom_fields_by_lua",
    },
    http_log = {
      "custom_fields_by_lua",
    },
    loggly = {
      "custom_fields_by_lua",
    },
    prometheus = {
      "per_consumer",
    },
    syslog = {
      "custom_fields_by_lua",
    },
    tcp_log = {
      "custom_fields_by_lua",
    },
    udp_log = {
      "custom_fields_by_lua",
    },
    zipkin = {
      "tags_header",
    }
  }

  local fields_2004001002 = {
    redis = {
      "connect_timeout",
      "keepalive_backlog",
      "keepalive_pool_size",
      "read_timeout",
      "send_timeout",
    },
    syslog = {
      "facility",
    },
  }

  if config_table and config_table["plugins"] then
    -- Merge dataplane unknown fields; if needed based on DP version
    local unknown_fields = fields_2004001002
    if dp_version_num() < 2003003003 then
      for k, v in pairs(fields_2003003003) do
        if unknown_fields[k] then
          for _, cv in ipairs(v) do
            table.insert(unknown_fields[k], cv)
          end
        else
          unknown_fields[k] = v
        end
      end
    end


    invalidate_keys_from_config(config_table["plugins"], unknown_fields)
  end
end

local function update_payload(payload, log_suffix)
  if is_older_dataplane() then
    local inflated_payload, err = inflate_gzip(payload)
    if inflated_payload then
      inflated_payload = cjson_decode(inflated_payload)
      handle_config_removal(inflated_payload["config_table"])

      local deflated_payload = cjson_encode(inflated_payload)
      deflated_payload, err = deflate_gzip(deflated_payload)
      if deflated_payload then
        return deflated_payload
      else
        ngx_log(ngx_WARN, _log_prefix, "unable to deflate configuration for data plane: ", err, log_suffix)
        return payload
      end
    else
      ngx_log(ngx_WARN, _log_prefix, "unable to inflate configuration for data plane: ", err, log_suffix)
      return payload
    end
  end

  return payload
end
-- XXX EE ]]

local function invalidate_keys_from_config(config_plugins, keys)
  if not config_plugins then
    return false
  end

  local has_update

  for _, t in ipairs(config_plugins) do
    local config = t and t["config"]
    if config then
      local name = gsub(t["name"], "-", "_")

      -- Handle Redis configurations (regardless of plugin)
      if config.redis then
        local config_plugin_redis = config.redis
        for _, key in ipairs(keys["redis"]) do
          if config_plugin_redis[key] ~= nil then
            config_plugin_redis[key] = nil
            has_update = true
          end
        end
      end

      -- Handle fields in specific plugins
      if keys[name] ~= nil then
        for _, key in ipairs(keys[name]) do
          if config[key] ~= nil then
            config[key] = nil
            has_update = true
          end
        end
      end
    end
  end

  return has_update
end

local function dp_version_num(dp_version)
  local base = 1000000000
  local version_num = 0
  for _, v in ipairs(utils.split(dp_version, ".", 4)) do
    v = v:match("^(%d+)")
    version_num = version_num + base * tonumber(v, 10) or 0
    base = base / 1000
  end

  return version_num
end
-- for test
_M._dp_version_num = dp_version_num

local function get_removed_fields(dp_version_number)
  local unknown_fields = {}
  local has_fields

  -- Merge dataplane unknown fields; if needed based on DP version
  for v, list in pairs(REMOVED_FIELDS) do
    if dp_version_number < v then
      has_fields = true
      for plugin, fields in pairs(list) do
        if not unknown_fields[plugin] then
          unknown_fields[plugin] = {}
        end
        for _, k in ipairs(fields) do
          table.insert(unknown_fields[plugin], k)
        end
      end
    end
  end

  return has_fields and unknown_fields or nil
end
-- for test
_M._get_removed_fields = get_removed_fields

-- returns has_update, modified_deflated_payload, err
local function update_compatible_payload(payload, dp_version, log_suffix)
  local fields = get_removed_fields(dp_version_num(dp_version))

  if fields then
    payload = utils.deep_copy(payload, false)
    local config_table = payload["config_table"]
    local has_update = invalidate_keys_from_config(config_table["plugins"], fields)

    if has_update then
      local deflated_payload, err = deflate_gzip(cjson_encode(payload))
      if deflated_payload then
        return true, deflated_payload
      else
        return true, nil, err
      end
    end
  end

  return false, nil, nil
end
-- for test
_M._update_compatible_payload = update_compatible_payload

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
  local shm_key_name = "clustering:cp_plugins_configured:worker_" .. ngx.worker.id()
  kong_dict:set(shm_key_name, cjson_encode(self.plugins_configured));
  ngx_log(ngx_DEBUG, "plugin configuration map key: " .. shm_key_name .. " configuration: ", kong_dict:get(shm_key_name))

  local config_hash = self:calculate_config_hash(config_table)

  local payload = {
    type = "reconfigure",
    timestamp = ngx_now(),
    config_table = config_table,
    config_hash = config_hash,
  }

  if not payload then
    return nil, err
  end
  self.reconfigure_payload = payload

  payload, err = deflate_gzip(cjson_encode(payload))
  if not payload then
    return nil, err
  end

  self.current_config_hash = config_hash
  self.deflated_reconfigure_payload = payload

  return payload, nil, config_hash
end


function _M:push_config()
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

  ngx_log(ngx_DEBUG, _log_prefix, "config pushed to ", n, " clients")
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

      -- [[ XXX EE: Handle special case for vault-auth plugin whose plugin
      --            version did not correspond to the actual release version
      --            and was fixed during BasePlugin inheritance removal.
      --
      -- Note: These vault-auth plugins in the older dataplanes are compatible
      if name == "vault-auth" and is_older_dataplane() and
        dp_plugin.version == "1.0.0" then
        ngx_log(ngx_DEBUG, _log_prefix, "data plane plugin vault-auth version ",
          "1.0.0 was incorrectly versioned, but is compatible")
        dp_plugin = cp_plugin
      end
      -- XXX EE ]]

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

  local _

  -- use mutual TLS authentication
  local ok, err = self:validate_client_cert(ngx_var.ssl_client_raw_cert, _log_prefix, log_suffix)
  if not ok then
    ngx_log(ngx_ERR, err)
    return ngx_exit(444)
  end

  if err then
    ngx_log(ngx_ERR, _log_prefix, err, log_suffix)
    return ngx_exit(ngx_CLOSE)
  end

  if not dp_id then
    ngx_log(ngx_WARN, _log_prefix, "data plane didn't pass the id", log_suffix)
    ngx_exit(400)
  end

  if not dp_version then
    ngx_log(ngx_WARN, _log_prefix, "data plane didn't pass the version", log_suffix)
    ngx_exit(400)
  end

  local wb, err = ws_server:new(WS_OPTS)
  if not wb then
    ngx_log(ngx_ERR, _log_prefix, "failed to perform server side websocket handshake: ", err, log_suffix)
    return ngx_exit(ngx_CLOSE)
  end

  -- connection established
  -- receive basic info
  local data, typ
  data, typ, err = wb:recv_frame()
  if err then
    err = "failed to receive websocket basic info frame: " .. err

  elseif typ == "binary" then
    if not data then
      err = "failed to receive websocket basic info data"

    else
      data, err = cjson_decode(data)
      if type(data) ~= "table" then
        if err then
          err = "failed to decode websocket basic info data: " .. err
        else
          err = "failed to decode websocket basic info data"
        end

      else
        if data.type ~= "basic_info" then
          err =  "invalid basic info data type: " .. (data.type  or "unknown")

        else
          if type(data.plugins) ~= "table" then
            err =  "missing plugins in basic info data"
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

  local dp_plugins_map = plugins_list_to_map(data.plugins)
  local config_hash = string.rep("0", 32) -- initial hash
  local last_seen = ngx_time()
  local sync_status = CLUSTERING_SYNC_STATUS.UNKNOWN
  local purge_delay = self.conf.cluster_data_plane_purge_delay
  local update_sync_status = function()
    local ok, err = kong.db.clustering_data_planes:upsert({ id = dp_id, }, {
      last_seen = last_seen,
      config_hash = config_hash ~= "" and config_hash or nil,
      hostname = dp_hostname,
      ip = dp_ip,
      version = dp_version,
      sync_status = sync_status, -- TODO: import may have been failed though
    }, { ttl = purge_delay })
    if not ok then
      ngx_log(ngx_ERR, _log_prefix, "unable to update clustering data plane status: ", err, log_suffix)
    end
  end

  _, err, sync_status = self:check_version_compatibility(dp_version, dp_plugins_map, log_suffix)
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

  self.clients[wb] = queue

  if not self.deflated_reconfigure_payload then
    _, err = self:export_deflated_reconfigure_payload()
  end

  if self.deflated_reconfigure_payload then
    -- initial configuration compatibility for sync status variable
    _, _, sync_status = self:check_configuration_compatibility(dp_plugins_map)

    table_insert(queue, self.deflated_reconfigure_payload)
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

      else
        if typ == "close" then
          ngx_log(ngx_DEBUG, _log_prefix, "received close frame from data plane", log_suffix)
          return
        end

        if not data then
          return nil, "did not receive ping frame from data plane"
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

        else -- is reconfigure
          local previous_sync_status = sync_status
          ok, err, sync_status = self:check_configuration_compatibility(dp_plugins_map)
          if ok then
            -- [[ XXX EE:
            --   - Handle redis timeout changes and syslog fields added in 2.5.0.0
            --   - Handle log, prometheus, and zipkin fields added in 2.4.1.0
            payload = update_payload(payload, log_suffix)
            -- XXX EE ]]

            local has_update, deflated_payload, err = update_compatible_payload(self.reconfigure_payload, dp_version)
            if not has_update then -- no modification, use the cached payload
              deflated_payload = self.deflated_reconfigure_payload
            elseif err then
              ngx_log(ngx_WARN, "unable to update compatible payload: ", err, ", the unmodified config ",
                      "is returned", log_suffix)
              deflated_payload = self.deflated_reconfigure_payload
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

          else
            ngx_log(ngx_WARN, _log_prefix, "unable to send updated configuration to data plane: ", err, log_suffix)
            if sync_status ~= previous_sync_status then
              update_sync_status()
            end
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

  --TODO: should we update disconnect data plane status?
  --sync_status = CLUSTERING_SYNC_STATUS.UNKNOWN
  --update_sync_status()

  if not ok then
    ngx_log(ngx_ERR, _log_prefix, err, log_suffix)
    return ngx_exit(ngx_ERR)
  end

  if perr then
    ngx_log(ngx_ERR, _log_prefix, perr, log_suffix)
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
    ngx_log(ngx_ERR, _log_prefix, "unable to export initial config from database: ", err)
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
