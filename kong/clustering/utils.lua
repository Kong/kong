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

local type = type
local tonumber = tonumber
local ipairs = ipairs
local table_insert = table.insert
local table_concat = table.concat
local process_type = require("ngx.process").type

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
  local version_num = 0
  for _, v in ipairs(utils.split(version, ".", 4)) do
    v = v:match("^(%d+)")
    version_num = version_num + base * tonumber(v, 10) or 0
    base = base / 1000
  end

  return version_num
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


return _M
