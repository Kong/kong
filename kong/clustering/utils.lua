local constants = require("kong.constants")
local ws_client = require("resty.websocket.client")
local ws_server = require("resty.websocket.server")
local parse_url = require("socket.url").parse
local process_type = require("ngx.process").type

local type = type
local table_insert = table.insert
local table_concat = table.concat
local encode_base64 = ngx.encode_base64
local worker_id = ngx.worker.id
local fmt = string.format

local kong = kong

local ngx = ngx
local ngx_log = ngx.log
local ngx_DEBUG = ngx.DEBUG
local ngx_WARN = ngx.WARN
local ngx_ERR = ngx.ERR
local ngx_CLOSE = ngx.HTTP_CLOSE

local _log_prefix = "[clustering] "

local KONG_VERSION = kong.version

local prefix = kong.configuration.prefix or require("pl.path").abspath(ngx.config.prefix())
local CLUSTER_PROXY_SSL_TERMINATOR_SOCK = fmt("unix:%s/cluster_proxy_ssl_terminator.sock", prefix)

local _M = {}


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


local WS_OPTS = {
  timeout = constants.CLUSTERING_TIMEOUT,
  max_payload_len = kong.configuration.cluster_max_payload,
}

-- TODO: pick one random CP
function _M.connect_cp(dp, endpoint, protocols)
  local conf = dp.conf
  local address = conf.cluster_control_plane .. endpoint

  local c = assert(ws_client:new(WS_OPTS))
  local uri = "wss://" .. address .. "?node_id=" ..
              kong.node.get_id() ..
              "&node_hostname=" .. kong.node.get_hostname() ..
              "&node_version=" .. KONG_VERSION

  local opts = {
    ssl_verify = true,
    client_cert = dp.cert.cdata,
    client_priv_key = dp.cert_key,
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


function _M.connect_dp(dp_id, dp_hostname, dp_ip, dp_version)
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
  if kong.configuration.privileged_agent then
    return process_type() == "privileged agent"
  end

  return worker_id() == 0
end


return _M
