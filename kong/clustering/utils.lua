-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local constants = require("kong.constants")
local openssl_x509 = require("resty.openssl.x509")
local ssl = require("ngx.ssl")
local http = require("resty.http")
local ws_client = require("resty.websocket.client")
local ws_server = require("resty.websocket.server")
local utils = require("kong.tools.utils")
local meta = require("kong.meta")
local ee_meta = require("kong.enterprise_edition.meta")
local regex_router_migrate = require("kong.clustering.compat.regex_router_path_280_300")

local type = type
local tonumber = tonumber
local ipairs = ipairs
local table_insert = table.insert
local table_concat = table.concat
local table_remove = table.remove
local gsub = string.gsub
local process_type = require("ngx.process").type
local null = ngx.null

local kong = kong

local ngx = ngx
local ngx_var = ngx.var
local ngx_log = ngx.log
local ngx_DEBUG = ngx.DEBUG
local ngx_INFO = ngx.INFO
local ngx_NOTICE = ngx.NOTICE
local ngx_WARN = ngx.WARN
local ngx_ERR = ngx.ERR
local ngx_CLOSE = ngx.HTTP_CLOSE

local _log_prefix = "[clustering] "

local REMOVED_FIELDS = require("kong.clustering.compat.removed_fields")
local MAJOR_MINOR_PATTERN = "^(%d+)%.(%d+)%.%d+"
local CLUSTERING_SYNC_STATUS = constants.CLUSTERING_SYNC_STATUS
local OCSP_TIMEOUT = constants.CLUSTERING_OCSP_TIMEOUT

local KONG_VERSION = kong.version

local EMPTY = {}

local _M = {}


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

local function check_kong_version_compatibility(cp_version, dp_version, log_suffix)
  local major_cp, minor_cp = extract_major_minor(cp_version)
  local major_dp, minor_dp = extract_major_minor(dp_version)

  if not major_cp then
    return nil, "data plane version " .. dp_version .. " is incompatible with control plane version",
    CLUSTERING_SYNC_STATUS.KONG_VERSION_INCOMPATIBLE
  end

  if not major_dp then
    return nil, "data plane version is incompatible with control plane version " ..
      cp_version .. " (" .. major_cp .. ".x.y are accepted)",
    CLUSTERING_SYNC_STATUS.KONG_VERSION_INCOMPATIBLE
  end

  -- special case for 3.0 CP and 2.8 DP
  if major_cp == 3 and minor_cp == 0 and major_dp == 2 and minor_dp == 8 then
    return true, nil, CLUSTERING_SYNC_STATUS.NORMAL
  end

  if major_cp ~= major_dp then
    return nil, "data plane version " .. dp_version ..
      " is incompatible with control plane version " ..
      cp_version .. " (" .. major_cp .. ".x.y are accepted)",
    CLUSTERING_SYNC_STATUS.KONG_VERSION_INCOMPATIBLE
  end

  if minor_cp < minor_dp then
    return nil, "data plane version " .. dp_version ..
      " is incompatible with older control plane version " .. cp_version,
    CLUSTERING_SYNC_STATUS.KONG_VERSION_INCOMPATIBLE
  end

  if minor_cp ~= minor_dp then
    local msg = "data plane minor version " .. dp_version ..
      " is different to control plane minor version " ..
      cp_version

    ngx_log(ngx_INFO, _log_prefix, msg, log_suffix or "")
  end

  return true, nil, CLUSTERING_SYNC_STATUS.NORMAL
end


local function validate_shared_cert(cert_digest)
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

  if digest ~= cert_digest then
    return nil, "data plane presented incorrect client certificate during handshake (expected: " ..
      cert_digest .. ", got: " .. digest .. ")"
  end

  return true
end

local check_for_revocation_status
do
  local get_full_client_certificate_chain = require("resty.kong.tls").get_full_client_certificate_chain
  check_for_revocation_status = function()
    --- XXX EE: ensure the OCSP code path is isolated
    local ocsp = require("ngx.ocsp")
    --- EE

    local cert, err = get_full_client_certificate_chain()
    if not cert then
      return nil, err or "no client certificate"
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
        ["Content-Type"] = "application/ocsp-request",
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

_M.check_for_revocation_status = check_for_revocation_status

local function validate_connection_certs(conf, cert_digest)
  local _, err

  -- use mutual TLS authentication
  if conf.cluster_mtls == "shared" then
    _, err = validate_shared_cert(cert_digest)

  elseif conf.cluster_ocsp ~= "off" then
    local ok
    ok, err = check_for_revocation_status()
    if ok == false then
      err = "data plane client certificate was revoked: " ..  err

    elseif not ok then
      if conf.cluster_ocsp == "on" then
        err = "data plane client certificate revocation check failed: " .. err

      else
        ngx_log(ngx_WARN, _log_prefix, "data plane client certificate revocation check failed: ", err)
        err = nil
      end
    end
  end

  if err then
    return nil, err
  end

  return true
end


function _M.plugins_list_to_map(plugins_list)
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

_M.check_kong_version_compatibility = check_kong_version_compatibility

function _M.check_version_compatibility(obj, dp_version, dp_plugin_map, log_suffix)
  local ok, err, status = check_kong_version_compatibility(KONG_VERSION, dp_version, log_suffix)
  local major_cp, minor_cp = extract_major_minor(KONG_VERSION)
  local major_dp, minor_dp = extract_major_minor(dp_version)
  if not ok then
    return ok, err, status
  end

  for _, plugin in ipairs(obj.plugins_list) do
    local name = plugin.name
    local cp_plugin = obj.plugins_map[name]
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

        -- special case for 3.0 CP and 2.8 DP
        if major_cp == 3 and minor_cp == 0 and major_dp == 2 and minor_dp == 8 then
          goto continue
        end

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

    ::continue::
  end

  return true, nil, CLUSTERING_SYNC_STATUS.NORMAL
end


local function version_num(version)
  local base = 1000000000
  local num = 0
  for _, v in ipairs(utils.split(version, ".", 4)) do
    v = v:match("^(%d+)")
    num = num + base * (tonumber(v, 10) or 0)
    base = base / 1000
  end

  return num
end

_M.version_num = version_num


function _M.check_configuration_compatibility(obj, dp_plugin_map, dp_version)
  local cp_version_num = version_num(meta.version)
  local dp_version_num = version_num(dp_version)

  for _, plugin in ipairs(obj.plugins_list) do
    if obj.plugins_configured[plugin.name] then
      local name = plugin.name
      local cp_plugin = obj.plugins_map[name]
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
      -- Note: These vault-auth plugins in the legacy dataplanes are compatible
      if name == "vault-auth" and dp_plugin.version == "1.0.0" then
        ngx_log(ngx_DEBUG, _log_prefix, "data plane plugin vault-auth version ",
          "1.0.0 was incorrectly versioned, but is compatible")
        dp_plugin = cp_plugin
      elseif (name == "rate-limiting-advanced" or
              name == "openid-connect" or
              name == "canary") and dp_version_num < 2006000000 --[[ 2.6.0.0 ]] then
        -- Add special error message for partially compatible plugins.
        --
        -- Note: These are plugins that get configuration values changed before
        -- they are pushed to the dataplanes.
        ngx_log(ngx_WARN, _log_prefix, "data plane plugin openid-connect version ",
          dp_plugin.version, " is partially compatible with version ", cp_plugin.version,
          "; it is strongly recommended to upgrade your data plane version ", dp_version,
          " to version ", KONG_VERSION)
        dp_plugin = cp_plugin
      end
      -- XXX EE ]]

      if cp_plugin.version and dp_plugin.version then
        -- CP plugin needs to match DP plugins with major version
        -- CP must have plugin with equal or newer version than that on DP

        -- special case for 3.0 CP and 2.8 DP
        -- adding 3.0 cp check in case we forget to remove this line after 3.1
        if dp_version_num >= 2008000000 and dp_version_num < 3000000000 and
          cp_version_num >= 3000000000 and cp_version_num < 3001000000
        then
          goto continue
        end

        if cp_plugin.major ~= dp_plugin.major or
          cp_plugin.minor < dp_plugin.minor then
          local msg = "configured data plane " .. name .. " plugin version " .. dp_plugin.version ..
                      " is different to control plane plugin version " .. cp_plugin.version
          return nil, msg, CLUSTERING_SYNC_STATUS.PLUGIN_VERSION_INCOMPATIBLE
        end
      end
    end

    ::continue::
  end

  local conf = (obj.reconfigure_payload or EMPTY).config_table or EMPTY

  if dp_version_num < 3000000000 then
    -- [[ XXX EE: Check for any WebSocket protocols
    --
    -- refactor me if/when adding new protocols becomes a regular thing
    local WS, WSS = "ws", "wss"

    local msg = "%s '%s' protocol '%s' is incompatible with data plane version %s"

    -- service.protocol
    local services = conf.services or EMPTY
    for _, service in ipairs(services) do
      local proto = service.protocol
      if proto == WS or proto == WSS then
        return nil,
               msg:format("service", service.id, proto, dp_version),
               CLUSTERING_SYNC_STATUS.SERVICE_PROTOCOL_INCOMPATIBLE
      end
    end

    -- route.protocols
    local routes = conf.routes or EMPTY
    for _, route in ipairs(routes) do
      if type(route.protocols) == "table" then
        for _, proto in ipairs(route.protocols) do
          if proto == WS or proto == WSS then
            return nil,
                   msg:format("route", route.id, proto, dp_version),
                   CLUSTERING_SYNC_STATUS.ROUTE_PROTOCOL_INCOMPATIBLE
          end
        end
      end
    end

    -- plugin.protocols
    local plugins = conf.plugins or EMPTY
    for _, plugin in ipairs(plugins) do
      if type(plugin.protocols) == "table" then
        local has_non_ws_proto = false
        local ws_proto = nil

        for _, proto in ipairs(plugin.protocols) do
          if proto == WS or proto == WSS then
            ws_proto = proto
          else
            has_non_ws_proto = true
          end
        end

        -- if the plugin has a mix of WS and non-WS protocols, we can handle
        -- that when updating the config payload later on
        --
        -- if the plugin _only_ has WS protocols, then it's probably not safe
        -- to continue
        if ws_proto and not has_non_ws_proto then
          return nil,
                 msg:format("plugin", plugin.id, ws_proto, dp_version),
                 CLUSTERING_SYNC_STATUS.PLUGIN_PROTOCOL_INCOMPATIBLE
        end
      end
    end
    -- XXX EE ]]

    local upstreams = conf.upstreams or EMPTY
    local msg = "upstream %s hash_on (%q) or hash_fallback (%q) is " ..
                "incompatible with data plane version %s"

    for _, upstream in ipairs(upstreams) do
      local hash_on = upstream.hash_on
      local hash_fallback = upstream.hash_fallback

      if hash_on == "path"
        or hash_on == "query_arg"
        or hash_on == "uri_capture"
        or hash_fallback == "path"
        or hash_fallback == "query_arg"
        or hash_fallback == "uri_capture"
      then
        return nil,
               msg:format(upstream.id, hash_on, hash_fallback, dp_version),
               CLUSTERING_SYNC_STATUS.UPSTREAM_HASH_INCOMPATIBLE
      end
    end
  end

  if dp_version_num < 2008001003 then
    -- [[ XXX EE: do not send vault entities to DP <2.8.1.3, there is a bug
    --            and no vault backends are enabled.
    if conf.vaults then
      conf.vaults = nil
      ngx_log(ngx_WARN, _log_prefix, "vault backends of data plane version ",  dp_version,
        " are not compatible with version ", KONG_VERSION, "; it is strongly recommended to ",
        "upgrade your data plane to version ", KONG_VERSION)
    end
    -- XXX EE ]]
  end

  -- TODO: DAOs are not checked in any way at the moment. For example if plugin introduces a new DAO in
  --       minor release and it has entities, that will most likely fail on data plane side, but is not
  --       checked here.

  return true, nil, CLUSTERING_SYNC_STATUS.NORMAL
end


--- Return the highest supported Hybrid mode protocol version.
function _M.check_protocol_support(conf, cert, cert_key)
  local params = {
    scheme = "https",
    method = "HEAD",

    ssl_verify = true,
    ssl_client_cert = cert,
    ssl_client_priv_key = cert_key,
  }

  if conf.cluster_mtls == "shared" then
    params.ssl_server_name = "kong_clustering"

  else
    -- server_name will be set to the host if it is not explicitly defined here
    if conf.cluster_server_name ~= "" then
      params.ssl_server_name = conf.cluster_server_name
    end
  end

  local c = http.new()
  local res, err = c:request_uri(
    "https://" .. conf.cluster_control_plane .. "/v1/wrpc", params)
  if not res then
    return nil, err
  end

  if res.status == 404 then
    return "v0"
  end

  return "v1"   -- wrpc
end


local WS_OPTS = {
  timeout = constants.CLUSTERING_TIMEOUT,
  max_payload_len = kong.configuration.cluster_max_payload,
}

-- TODO: pick one random CP
function _M.connect_cp(endpoint, conf, cert, cert_key, protocols)
  local address = conf.cluster_control_plane .. endpoint

  local c = assert(ws_client:new(WS_OPTS))
  local uri = "wss://" .. address .. "?node_id=" ..
              kong.node.get_id() ..
              "&node_hostname=" .. kong.node.get_hostname() ..
              "&node_version=" .. KONG_VERSION

  local opts = {
    ssl_verify = true,
    client_cert = cert,
    client_priv_key = cert_key,
    protocols = protocols,
  }

  if conf.cluster_mtls == "shared" then
    opts.server_name = "kong_clustering"

  else
    -- server_name will be set to the host if it is not explicitly defined here
    if conf.cluster_server_name ~= "" then
      opts.server_name = conf.cluster_server_name
    end
  end

  local ok, err = c:connect(uri, opts)
  if not ok then
    return nil, uri, err
  end

  return c
end


function _M.connect_dp(conf, cert_digest,
                       dp_id, dp_hostname, dp_ip, dp_version)
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

  local ok, err = validate_connection_certs(conf, cert_digest)
  if not ok then
    ngx_log(ngx_ERR, _log_prefix, err)
    return nil, nil, ngx.HTTP_CLOSE
  end

  if not dp_id then
    ngx_log(ngx_WARN, _log_prefix, "data plane didn't pass the id", log_suffix)
    return nil, nil, 400
  end

  if not dp_version then
    ngx_log(ngx_WARN, _log_prefix, "data plane didn't pass the version", log_suffix)
    return nil, nil, 400
  end

  local wb, err = ws_server:new(WS_OPTS)

  if not wb then
    ngx_log(ngx_ERR, _log_prefix, "failed to perform server side websocket handshake: ", err, log_suffix)
    return nil, nil, ngx_CLOSE
  end

  return wb, log_suffix
end


function _M.is_dp_worker_process()
  return process_type() == "privileged agent"
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

                -- maybe field_element is a key to be removed
                elseif config[key][field_element] ~= nil then
                  config[key][field_element] = nil
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


-- returns has_update, modified_config_table
function _M.update_compatible_payload(config_table, dp_version, log_suffix)
  local cp_version_num = version_num(ee_meta.version)
  local dp_version_num = version_num(dp_version)

  -- if the CP and DP have the same version, avoid the payload
  -- copy and compatibility updates
  if cp_version_num == dp_version_num then
    return false
  end

  local has_update = false
  config_table = utils.deep_copy(config_table, false)
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
            local metrics = config["metrics"]
            if metrics then
              local origin_config = origin_config_table["plugins"][i]["config"]
              local removed_metrics = {
                status_count_per_workspace = true,
                status_count_per_user_per_route = true,
                shdict_usage = true,
                cache_datastore_hits_total = true,
                cache_datastore_misses_total = true,
              }

              for idx = #metrics, 1, -1 do
                local metric_name = metrics[idx]["name"]
                if removed_metrics[metric_name] then
                  ngx_log(ngx_WARN, _log_prefix, "statsd plugin for Kong Gateway v" .. KONG_VERSION ..
                    " supports metric '" .. metric_name .. "' which is incompatible with" ..
                    " dataplane version " .. dp_version .. " and will be removed", log_suffix)
                  table.remove(metrics, idx)
                  has_update = true
                end
              end

              for _, metric in ipairs(metrics) do
                if not metric.consumer_identifier or metric.consumer_identifier == null then
                  metric.consumer_identifier = origin_config.consumer_identifier_default
                  has_update = true
                end

                if metric.service_identifier then
                  metric.service_identifier = nil
                  has_update = true
                end

                if metric.workspace_identifier then
                  metric.workspace_identifier = nil
                  has_update = true
                end
              end
            end
          end

          if t["name"] == "http-log" then
            if config["headers"] then
              -- no warning, because I only change the internal data type
              for header_name, header_value in pairs(config["headers"]) do
                local values = {}
                local parts = utils.split(header_value, ",")
                for _, v in ipairs(parts) do
                  table_insert(values, v)
                end
                config["headers"][header_name] = values
              end
              has_update = true
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

  --[[ range in [3.0.0.0 - 3.0.999.9] ]]
  if dp_version_num > 2999999999 and dp_version_num < 3001000000 then
    if config_table["plugins"] then
      for _, t in ipairs(config_table["plugins"]) do
        local config = t and t["config"]
        if config then
          if t["name"] == "request-transformer-advanced" then
            if config["dots_in_keys"] then
              ngx_log(ngx_WARN, _log_prefix, "Kong Gateway v" .. KONG_VERSION ..
                " contains configuration 'dots_in_keys'",
                " which is incompatible with dataplane version " .. dp_version .. " and will",
                " be removed.", log_suffix)
              config["dots_in_keys"] = nil
              has_update = true
            end
            if config["replace"]["json_types"] then
              ngx_log(ngx_WARN, _log_prefix, "Kong Gateway v" .. KONG_VERSION ..
                " contains configuration 'replace.json_types'",
                " which is incompatible with dataplane version " .. dp_version .. " and will",
                " be removed.", log_suffix)
              config["replace"]["json_types"] = nil
              has_update = true
            end
            if config["add"]["json_types"] then
              ngx_log(ngx_WARN, _log_prefix, "Kong Gateway v" .. KONG_VERSION ..
                " contains configuration 'add.json_types'",
                " which is incompatible with dataplane version " .. dp_version .. " and will",
                " be removed.", log_suffix)
              config["add"]["json_types"] = nil
              has_update = true
            end
            if config["append"]["json_types"] then
              ngx_log(ngx_WARN, _log_prefix, "Kong Gateway v" .. KONG_VERSION ..
                " contains configuration 'append.json_types'",
                " which is incompatible with dataplane version " .. dp_version .. " and will",
                " be removed.", log_suffix)
              config["append"]["json_types"] = nil
              has_update = true
            end
          end
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
    return true, config_table
  end

  return false, nil
end


return _M
