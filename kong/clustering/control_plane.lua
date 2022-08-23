-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local _M = {}
local _MT = { __index = _M, }


local semaphore = require("ngx.semaphore")
local cjson = require("cjson.safe")
local declarative = require("kong.db.declarative")
local utils = require("kong.tools.utils")
local clustering_utils = require("kong.clustering.utils")
local constants = require("kong.constants")
local ee_meta = require("kong.enterprise_edition.meta")
local regex_router_migrate = require("kong.clustering.compat.regex_router_path_280_300")

local string = string
local setmetatable = setmetatable
local type = type
local pcall = pcall
local pairs = pairs
local yield = utils.yield
local ipairs = ipairs
local ngx = ngx
local null = ngx.null
local ngx_log = ngx.log
local timer_at = ngx.timer.at
local cjson_decode = cjson.decode
local cjson_encode = cjson.encode
local kong = kong
local ngx_exit = ngx.exit
local exiting = ngx.worker.exiting
local ngx_time = ngx.time
local ngx_now = ngx.now
local ngx_update_time = ngx.update_time
local ngx_var = ngx.var
local table_insert = table.insert
local table_remove = table.remove
local table_concat = table.concat
local sub = string.sub
local gsub = string.gsub
local deflate_gzip = utils.deflate_gzip

local calculate_config_hash = require("kong.clustering.config_helper").calculate_config_hash
local version_num = clustering_utils.version_num

local kong_dict = ngx.shared.kong
local KONG_VERSION = kong.version
local ngx_DEBUG = ngx.DEBUG
local ngx_NOTICE = ngx.NOTICE
local ngx_WARN = ngx.WARN
local ngx_ERR = ngx.ERR
local ngx_OK = ngx.OK
local ngx_ERROR = ngx.ERROR
local ngx_CLOSE = ngx.HTTP_CLOSE
local PING_INTERVAL = constants.CLUSTERING_PING_INTERVAL
local PING_WAIT = PING_INTERVAL * 1.5
local CLUSTERING_SYNC_STATUS = constants.CLUSTERING_SYNC_STATUS
local DECLARATIVE_EMPTY_CONFIG_HASH = constants.DECLARATIVE_EMPTY_CONFIG_HASH
local PONG_TYPE = "PONG"
local RECONFIGURE_TYPE = "RECONFIGURE"
local REMOVED_FIELDS = require("kong.clustering.compat.removed_fields")
local _log_prefix = "[clustering] "


local plugins_list_to_map = clustering_utils.plugins_list_to_map


local function handle_export_deflated_reconfigure_payload(self)
  local ok, p_err, err = pcall(self.export_deflated_reconfigure_payload, self)
  return ok, p_err or err
end


local function is_timeout(err)
  return err and sub(err, -7) == "timeout"
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


-- [[ XXX EE: TODO: Backport find_field_element function to OSS
local function find_field_element(table, field_element)
  if type(table) == "table" then
    for i, v in pairs(table) do
      if v == field_element then
        return i
      end
    end
  end

  return nil
end


-- [[ XXX EE: TODO: Backport function rename, logging, and element removal to OSS
--                  invalidate_keys_from_config => invalidate_items_from_config
local function invalidate_items_from_config(config_plugins, keys, log_suffix)
  if not config_plugins then
    return false
  end

  local has_update

  for _, t in ipairs(config_plugins) do
    local config = t and t["config"]
    if config then
      local name = gsub(t["name"], "-", "_")

      -- Handle Redis configurations (regardless of plugin)
      if config.redis and keys["redis"] then
        local config_plugin_redis = config.redis
        for _, key in ipairs(keys["redis"]) do
          if config_plugin_redis[key] ~= nil then
            ngx_log(ngx_WARN, _log_prefix, name, " plugin contains redis configuration '", key,
              "' which is incompatible with dataplane and will be ignored", log_suffix)
            config_plugin_redis[key] = nil
            has_update = true
          end
        end
      end

      -- Handle fields in specific plugins
      if keys[name] ~= nil then
        for key, field in pairs(keys[name]) do
          if type(field) == "table" then
            if config[key] ~= nil then
              for _, field_element in pairs(keys[name][key]) do
                local index = find_field_element(config[key], field_element)
                if index ~= nil then
                  ngx_log(ngx_WARN, _log_prefix, name, " plugin contains configuration '", key,
                    "' element '", field_element, "' which is incompatible with dataplane and will",
                    " be ignored", log_suffix)
                  table_remove(config[key], index)
                  has_update = true
                end
              end
            end
          else
            if config[field] ~= nil then
              ngx_log(ngx_WARN, _log_prefix, name, " plugin contains configuration '", field,
                "' which is incompatible with dataplane and will be ignored", log_suffix)
              config[field] = nil
              has_update = true
            end
          end
        end
      end
    end
  end

  return has_update
end

-- for test
_M._version_num = version_num

-- [[ XXX EE: TODO: Backport function changes and descriptive variable name change to OSS
local function get_removed_fields(dp_version_number)
  local unknown_fields_and_elements = {}
  local has_fields

  -- Merge dataplane unknown fields and field elements; if needed based on DP version
  for v, list in pairs(REMOVED_FIELDS) do
    if dp_version_number < v then
      has_fields = true
      for plugin, fields in pairs(list) do
        if not unknown_fields_and_elements[plugin] then
          unknown_fields_and_elements[plugin] = {}
        end
        for k, f in pairs(fields) do
          if type(f) == "table" then
            if not unknown_fields_and_elements[plugin][k] then
              unknown_fields_and_elements[plugin][k] = {}
            end

            for _, e in pairs(f) do
              table_insert(unknown_fields_and_elements[plugin][k], e)
            end
          else
            table_insert(unknown_fields_and_elements[plugin], f)
          end
        end
      end
    end
  end

  return has_fields and unknown_fields_and_elements or nil
end
-- for test
_M._get_removed_fields = get_removed_fields

local function kafka_mechanism_compat(conf, plugin_name, dp_version, log_suffix)
  if plugin_name ~= "kafka-log" and plugin_name ~= "kafka-upstream" then
    return false
  end
  if conf["authentication"] then
    if conf["authentication"]["mechanism"] == "SCRAM-SHA-512" then
      ngx_log(ngx_WARN, _log_prefix, "the kafka plugins for Kong Gateway v" .. KONG_VERSION ..
              " contains configuration mechanism='SCRAM-SHA-512', which is incompatible with",
              " dataplane version " .. dp_version .. " and will be set to 'SCRAM-SHA-256'.", log_suffix)
      conf["authentication"]["mechanism"] = "SCRAM-SHA-256"
      return true
    end
  end
  return false
end

-- returns has_update, modified_deflated_payload, err
local function update_compatible_payload(payload, dp_version, log_suffix)
  local cp_version_num = version_num(ee_meta.version)
  local dp_version_num = version_num(dp_version)

  -- if the CP and DP have the same version, avoid the payload
  -- copy and compatibility updates
  if cp_version_num == dp_version_num then
    return false
  end

  local has_update = false
  payload = utils.deep_copy(payload, false)
  local config_table = payload["config_table"]
  local origin_config_table = utils.deep_copy(config_table, false)

  local fields = get_removed_fields(dp_version_num)
  if fields and invalidate_items_from_config(config_table["plugins"], fields, log_suffix) then
    has_update = true
  end

  -- XXX EE: this should be moved in its own file (compat/config.lua). With a table
  -- similar to compat/remove_fields, each plugin could register a function to handle
  -- its compatibility issues.
  if dp_version_num < 3000000000 --[[ 3.0.0.0 ]] then
    -- migrations for route path
    -- explicit regex indicator: https://github.com/Kong/kong/pull/9027
    -- no longer urldecode regex: https://github.com/Kong/kong/pull/9024
    if config_table._format_version == "3.0" then
      regex_router_migrate(config_table)
      config_table._format_version = "2.1"
      -- this is not evadiable cause we need to change the _format_version unconditionally
      has_update = true
    end

    if config_table["plugins"] then
      for i, t in ipairs(config_table["plugins"]) do
        local config = t and t["config"]
        if config then
          if t["name"] == "zipkin" then
            if config["header_type"] and config["header_type"] == "datadog" then
              ngx_log(ngx_WARN, _log_prefix, "zipkin plugin for Kong Gateway v" .. KONG_VERSION ..
                      " contains configuration 'header_type=datadog', which is incompatible with",
                      " dataplane version " .. dp_version .. " and will be replaced with 'preserve'.", log_suffix)
              config["header_type"] = "preserve"
              has_update = true
            end

            if config["default_header_type"] and config["default_header_type"] == "datadog" then
              ngx_log(ngx_WARN, _log_prefix, "zipkin plugin for Kong Gateway v" .. KONG_VERSION ..
                      " contains configuration 'default_header_type=datadog', which is incompatible with",
                      " dataplane version " .. dp_version .. " and will be replaced with 'b3'.", log_suffix)
              config["header_type"] = "b3"
              has_update = true
            end
          end

          if t["name"] == "statsd-advanced" then
            if config["metrics"] then
              local origin_config = origin_config_table["plugins"][i]["config"]
              for _, metric in ipairs(config["metrics"]) do
                ngx_log(ngx_WARN, _log_prefix, "statsd-advanced plugin for Kong Gateway v" .. KONG_VERSION ..
                  " supports null of consumer_identifier, service_identifier, and workspace_identifier," ..
                  " which is incompatible with",
                  " dataplane version " .. dp_version .. " and will be replaced with the default value from" ..
                  " consumer_identifier_default, service_identifier_default, and workspace_identifier_default",
                  log_suffix)

                if not metric.consumer_identifier or metric.consumer_identifier == null then
                  metric.consumer_identifier = origin_config.consumer_identifier_default
                  has_update = true
                end
                if not metric.service_identifier or metric.service_identifier == null then
                  metric.service_identifier = origin_config.service_identifier_default
                  has_update = true
                end
                if not metric.workspace_identifier or metric.workspace_identifier == null then
                  metric.workspace_identifier = origin_config.workspace_identifier_default
                  has_update = true
                end
              end
            end
          end

          if t["name"] == "statsd" then
            -- rename the plugin name to statsd-advanced for backward compatibility
            -- as we removed the whole statsd-advanced
            t["name"] = "statsd-advanced"
            has_update = true
            local metrics = config["metrics"]
            if metrics then
              local origin_config = origin_config_table["plugins"][i]["config"]
              for _, metric in ipairs(metrics) do
                if not metric.consumer_identifier or metric.consumer_identifier == null then
                  metric.consumer_identifier = origin_config.consumer_identifier_default
                end
                if not metric.service_identifier or metric.service_identifier == null then
                  metric.service_identifier = origin_config.service_identifier_default
                end
                if not metric.workspace_identifier or metric.workspace_identifier == null then
                  metric.workspace_identifier = origin_config.workspace_identifier_default
                end
              end
            end
          end
        end


        -- remove `ws` and `wss` from plugin.protocols if found
        local protocols = t and t["protocols"]
        if type(protocols) == "table" then
          local found_ws_proto

          for _, proto in ipairs(protocols) do
            if proto == "ws" or proto == "wss" then
              found_ws_proto = true
              break
            end
          end

          if found_ws_proto then
            ngx_log(ngx_WARN, _log_prefix, t["name"], " plugin for Kong Gateway",
                    " v", KONG_VERSION, " contains WebSocket protocols (ws/wss),",
                    " which are incompatible with dataplane version ", dp_version,
                    " and will be removed")

            has_update = true
            local new = {}
            for _, proto in ipairs(protocols) do
              if proto ~= "ws" and proto ~= "wss" then
                table_insert(new, proto)
              end
            end
            t["protocols"] = new
          end
        end
      end
    end

    if config_table["upstreams"] then
      -- handle new upstream `hash_on` and `hash_fallback` options
      -- https://github.com/Kong/kong/pull/8701

      local field_names = {
        "hash_on_query_arg",
        "hash_fallback_query_arg",
        "hash_on_uri_capture",
        "hash_fallback_uri_capture",
      }

      local removed = {}

      for _, t in ipairs(config_table["upstreams"]) do
        -- At this point the upstream's hash fields are have been validated as
        -- safe for pre-3.0 data planes, but it might still have incompatible
        -- fields present. Example scenario:
        --
        -- 1. POST /upstreams name=test
        --                    hash_on=query_arg
        --                    hash_on_query_arg=test
        --
        -- 2. PATCH /upstream/test hash_on=ip
        --
        -- The `hash_on` field is compatible with <3.0, but there is now a
        -- dangling `hash_on_query_arg` arg field that must be removed.

        local n = 0
        for _, field in ipairs(field_names) do
          if t[field] ~= nil then
            n = n + 1
            removed[n] = field
            t[field] = nil
          end
        end

        if n > 0 then
          local removed_field_names = table_concat(removed, ", ", 1, n)
          ngx_log(ngx_WARN, _log_prefix, "Kong Gateway v", KONG_VERSION,
                  " contains upstream configuration (", removed_field_names, ")",
                  " which is incompatible with dataplane version ", dp_version,
                  " and will be removed.", log_suffix)
          has_update = true
        end
      end
    end


  end

  if dp_version_num < 2008001001 --[[ 2.8.1.1 ]] then
    if config_table["plugins"] then
      for _, t in ipairs(config_table["plugins"]) do
        local config = t and t["config"]
        if config then
          if kafka_mechanism_compat(config, t["name"], dp_version, log_suffix) then
            has_update = true
          end
        end
      end
    end
  end

  if dp_version_num < 2008000000 --[[ 2.8.0.0 ]] then
    local entity_removal = {
      "vaults_beta",
    }
    for _, entity in ipairs(entity_removal) do
      if config_table[entity] then
        ngx_log(ngx_WARN, _log_prefix, "Kong Gateway v" .. KONG_VERSION ..
                " contains configuration '" .. entity .. "'",
                " which is incompatible with dataplane version " .. dp_version .. " and will",
                " be removed.", log_suffix)
        config_table[entity] = nil
        has_update = true
      end
    end
    if config_table["plugins"] then
      for _, t in ipairs(config_table["plugins"]) do
        local config = t and t["config"]
        if config then
          if t["name"] == "openid-connect" then
            if config["session_redis_password"] then
              ngx_log(ngx_WARN, _log_prefix, "openid-connect plugin for Kong Gateway v" .. KONG_VERSION ..
                      " contains configuration session_redis_password, which is incompatible with",
                      " dataplane version " .. dp_version .. " and will be replaced with 'session_redis_auth'.", log_suffix)
              config["session_redis_auth"] = config["session_redis_password"]
              config["session_redis_password"] = nil
              has_update = true
            end
          end

          if t["name"] == "forward-proxy" then
            if config["http_proxy_host"] then
              ngx_log(ngx_WARN, _log_prefix, "forward-proxy plugin for Kong Gateway v" .. KONG_VERSION ..
                      " contains configuration http_proxy_host, which is incompatible with",
                      " dataplane version " .. dp_version .. " and will be replaced with 'proxy_host'.", log_suffix)
              config["proxy_host"] = config["http_proxy_host"]
              config["http_proxy_host"] = nil
              has_update = true
            end
            if config["http_proxy_port"] then
              ngx_log(ngx_WARN, _log_prefix, "forward-proxy plugin for Kong Gateway v" .. KONG_VERSION ..
                      " contains configuration http_proxy_port, which is incompatible with",
                      " dataplane version " .. dp_version .. " and will be replaced with 'proxy_port'.", log_suffix)
              config["proxy_port"] = config["http_proxy_port"]
              config["http_proxy_port"] = nil
            end
          end
        end
      end
    end
  end

  if dp_version_num < 2007000000 --[[ 2.7.0.0 ]] then
    local entity_removal = {
      "consumer_groups",
      "consumer_group_consumers",
      "consumer_group_plugins",
    }
    for _, entity in ipairs(entity_removal) do
      if config_table[entity] then
        ngx_log(ngx_WARN, _log_prefix, "Kong Gateway v" .. KONG_VERSION ..
                " contains configuration '" .. entity .. "'",
                " which is incompatible with dataplane version " .. dp_version .. " and will",
                " be removed.", log_suffix)
        config_table[entity] = nil
        has_update = true
      end
    end

    if config_table["services"] then
      for _, t in ipairs(config_table["services"]) do
        if t["enabled"] then
          ngx_log(ngx_WARN, _log_prefix, "Kong Gateway v" .. KONG_VERSION ..
                  " contains configuration 'services.enabled'",
                  " which is incompatible with dataplane version " .. dp_version .. " and will",
                  " be removed.", log_suffix)
          t["enabled"] = nil
          has_update = true
        end
      end
    end

    if config_table["plugins"] then
      for _, t in ipairs(config_table["plugins"]) do
        local config = t and t["config"]
        if config then
          -- TODO: Properly implemented nested field removal [datadog plugin]
          --       Note: This is not as straightforward due to field element
          --             removal implementation; this needs to be refactored
          if t["name"] == "datadog" then
            if config["metrics"] then
              for i, m in ipairs(config["metrics"]) do
                if m["stat_type"] == "distribution" then
                  ngx_log(ngx_WARN, _log_prefix, "datadog plugin for Kong Gateway v" .. KONG_VERSION ..
                          " contains metric '" .. m["name"] .. "' of type 'distribution' which is incompatible with",
                          " dataplane version " .. dp_version .. " and will be ignored.", log_suffix)
                  config["metrics"][i] = nil
                  has_update = true
                end
              end
            end
          end

          if t["name"] == "zipkin" then
            if config["header_type"] and config["header_type"] == "ignore" then
              ngx_log(ngx_WARN, _log_prefix, "zipkin plugin for Kong Gateway v" .. KONG_VERSION ..
                      " contains header_type=ignore, which is incompatible with",
                      " dataplane version " .. dp_version .. " and will be replaced with 'header_type=preserve'.", log_suffix)
              config["header_type"] = "preserve"
              has_update = true
            end
          end
        end
      end
    end
  end

  if dp_version_num < 2006000000 --[[ 2.6.0.0 ]] then
    if config_table["consumers"] then
      for _, t in ipairs(config_table["consumers"]) do
        if t["username_lower"] then
          ngx_log(ngx_WARN, _log_prefix, "Kong Gateway v" .. KONG_VERSION ..
                  " contains configuration 'consumer.username_lower'",
                  " which is incompatible with dataplane version " .. dp_version .. " and will",
                  " be removed.", log_suffix)
          t["username_lower"] = nil
          has_update = true
        end
      end
    end
    if config_table["oic_jwks"] then
      for _, t in ipairs(config_table["oic_jwks"]) do
        if t["jwks"] and t["jwks"].keys then
          for _, k in ipairs(t["jwks"].keys) do
            for _, e in ipairs({ "oth", "r", "t" }) do
              if k[e] then
                ngx_log(ngx_WARN, _log_prefix, "Kong Gateway v" .. KONG_VERSION ..
                        " contains configuration 'oic_jwks.jwks.keys[\"" .. e .. "\"]'",
                        " which is incompatible with dataplane version " .. dp_version .. " and will",
                        " be removed.", log_suffix)
                k[e] = nil
                has_update = true
              end
            end
          end
        end
      end
    end
    if config_table["plugins"] then
      for _, t in ipairs(config_table["plugins"]) do
        local config = t and t["config"]
        if config then
          -- TODO: Properly implemented nested field removal [acme plugin]
          --       Note: This is not as straightforward due to field element
          --             removal implementation; this needs to be refactored
          if t["name"] == "acme" then
            if config["storage_config"] and config["storage_config"].vault then
              for _, i in ipairs({ "auth_method", "auth_path", "auth_role", "jwt_path" }) do
                if config["storage_config"].vault[i] ~= nil then
                  ngx_log(ngx_WARN, _log_prefix, "acme plugin for Kong Gateway v" .. KONG_VERSION ..
                          "contains vault storage configuration '", i, "' which is incompatible with",
                          "dataplane version " .. dp_version .. " and will be ignored", log_suffix)
                  config["storage_config"].vault[i] = nil
                  has_update = true
                end
              end
            end
          end

          if t["name"] == "canary" then
            if config["hash"] == "header" then
              ngx_log(ngx_WARN, _log_prefix, t["name"], " plugin for Kong Gateway v" .. KONG_VERSION ..
                      " contains configuration 'hash=header'",
                      " which is incompatible with dataplane version " .. dp_version .. " and will",
                      " be replaced by 'hash=consumer'.", log_suffix)
              config["hash"] = "consumer" -- default
              has_update = true
            end
          end
          if t["name"] == "rate-limiting-advanced" then
            if config["strategy"] == "local" then
              ngx_log(ngx_WARN, _log_prefix, t["name"], " plugin for Kong Gateway v" .. KONG_VERSION ..
                      " contains configuration 'strategy=local'",
                      " which is incompatible with dataplane version " .. dp_version .. " and will",
                      " be replaced by 'strategy=redis' and 'sync_rate=-1'.", log_suffix)
              config["strategy"] = "redis"
              config["sync_rate"] = -1
              has_update = true
            elseif config["sync_rate"] and config["sync_rate"] > 0 and config["sync_rate"] < 1 then
              ngx_log(ngx_WARN, _log_prefix, t["name"], " plugin for Kong Gateway v" .. KONG_VERSION ..
                      " contains configuration 'sync_rate < 1'",
                      " which is incompatible with dataplane version " .. dp_version .. " and will",
                      " be replaced by 'sync_rate=1'.", log_suffix)
              config["sync_rate"] = 1
              has_update = true
            end

            if config["identifier"] == "path" then
              ngx_log(ngx_WARN, _log_prefix, t["name"], " plugin for Kong Gateway v" .. KONG_VERSION ..
                      " contains configuration 'identifier=path'",
                      " which is incompatible with dataplane version " .. dp_version .. " and will",
                      " be replaced by 'identifier=consumer'.", log_suffix)
              config["identifier"] = "consumer" -- default
              has_update = true
            end
          end
        end
      end
    end
  end

  if has_update then
    local deflated_payload, err = deflate_gzip(cjson_encode(payload))
    if deflated_payload then
      return true, deflated_payload
    else
      return true, nil, err
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
  kong_dict:set(shm_key_name, cjson_encode(self.plugins_configured))
  ngx_log(ngx_DEBUG, "plugin configuration map key: " .. shm_key_name .. " configuration: ", kong_dict:get(shm_key_name))

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
  ngx_log(ngx_DEBUG, _log_prefix, "config pushed to ", n, " data-plane nodes in " .. duration .. " seconds")
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
  local config_hash = DECLARATIVE_EMPTY_CONFIG_HASH -- initial hash
  local last_seen = ngx_time()
  local sync_status = CLUSTERING_SYNC_STATUS.UNKNOWN
  local purge_delay = self.conf.cluster_data_plane_purge_delay
  local update_sync_status = function()
    local ok
    ok, err = kong.db.clustering_data_planes:upsert({ id = dp_id, }, {
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

  local _
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
    _, err = handle_export_deflated_reconfigure_payload(self)
  end

  if self.deflated_reconfigure_payload then
    local _
    -- initial configuration compatibility for sync status variable
    _, _, sync_status = self:check_configuration_compatibility(dp_plugins_map, dp_version)

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
          ok, err, sync_status = self:check_configuration_compatibility(dp_plugins_map, dp_version)
          if ok then
            local has_update, deflated_payload, err = update_compatible_payload(self.reconfigure_payload, dp_version, log_suffix)
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
