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
local parse_url = require("socket.url").parse

local type = type
local table_insert = table.insert
local table_concat = table.concat
local encode_base64 = ngx.encode_base64
local worker_id = ngx.worker.id
local fmt = string.format

local kong = kong

local ngx = ngx
local ngx_var = ngx.var
local ngx_log = ngx.log
local ngx_DEBUG = ngx.DEBUG
local ngx_WARN = ngx.WARN
local ngx_ERR = ngx.ERR
local ngx_CLOSE = ngx.HTTP_CLOSE

local _log_prefix = "[clustering] "

local OCSP_TIMEOUT = constants.CLUSTERING_OCSP_TIMEOUT

local KONG_VERSION = kong.version

local prefix = kong.configuration.prefix or require("pl.path").abspath(ngx.config.prefix())
local CLUSTER_PROXY_SSL_TERMINATOR_SOCK = fmt("unix:%s/cluster_proxy_ssl_terminator.sock", prefix)

local _M = {}


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


local function parse_proxy_url(conf)
  local ret = {}
  local proxy_server = conf.proxy_server
  if proxy_server then
    -- assume proxy_server is validated in conf_loader
    local parsed = parse_url(proxy_server)
    if parsed.scheme == "https" then
      ret.proxy_url = CLUSTER_PROXY_SSL_TERMINATOR_SOCK
      -- hide other fields to avoid it being accidently used
      -- the connection details is statically rendered in nginx template

    else -- http
      ret.proxy_url = fmt("%s://%s:%s", parsed.scheme, parsed.host, parsed.port or 443)
      ret.scheme = parsed.scheme
      ret.host = parsed.host
      ret.port = parsed.port
    end

    if parsed.user and parsed.password then
      ret.proxy_authorization = "Basic " .. encode_base64(parsed.user  .. ":" .. parsed.password)
    end
  end

  return ret
end

_M.parse_proxy_url = parse_proxy_url


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

  if conf.cluster_use_proxy then
    local proxy_opts = parse_proxy_url(conf)
    opts.proxy_opts = {
      wss_proxy = proxy_opts.proxy_url,
      wss_proxy_authorization = proxy_opts.proxy_authorization,
    }

    ngx_log(ngx_DEBUG, _log_prefix,
            "using proxy ", proxy_opts.proxy_url, " to connect control plane")
  end

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
  return worker_id() == 0
end


return _M
