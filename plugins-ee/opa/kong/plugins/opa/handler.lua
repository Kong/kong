-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local ngx_ssl = require "ngx.ssl"
local cjson = require "cjson"
local http = require "resty.http"
local decision = require "kong.plugins.opa.decision"
local ngx = ngx
local kong = kong
local meta = require "kong.meta"
local pl_tablex = require "pl.tablex"


local OpaHandler = {
  -- execute logic in opa after auth plugins have run but before
  -- rate-limiting and any transformations run
  PRIORITY = 920,
  VERSION = meta.core_version,
}

local EMPTY = pl_tablex.readonly {}


local function build_opa_input(plugin_conf)
  local nctx = ngx.ctx
  local nvar = ngx.var

  local request_tls = {}
  local request_tls_ver = ngx_ssl.get_tls1_version_str()
  if request_tls_ver then
    request_tls = {
      version = request_tls_ver,
      cipher = ngx.var.ssl_cipher,
      client_verify = ngx.ctx.CLIENT_VERIFY_OVERRIDE or ngx.var.ssl_client_verify,
    }
  end

  local opa_input = {
    request = {
      http = {
        method = kong.request.get_method(),
        scheme = nvar.scheme,
        host = nvar.host,
        port = nctx.host_port or nvar.server_port,
        path = kong.request.get_path(),
        headers = kong.request.get_headers(),
        querystring = kong.request.get_query(),
        tls = request_tls,
      },
    },
    client_ip = nvar.remote_addr,
  }

  if plugin_conf.include_service_in_opa_input then
    opa_input.service = nctx.service
  end
  if plugin_conf.include_route_in_opa_input then
    opa_input.route = nctx.route
  end
  if plugin_conf.include_consumer_in_opa_input then
    opa_input.consumer = nctx.authenticated_consumer
  end
  if plugin_conf.include_body_in_opa_input then
    local body = kong.request.get_raw_body()
    opa_input.request.http.body = body
    opa_input.request.http.body_size = #body
  end
  if plugin_conf.include_parsed_json_body_in_opa_input and
    kong.request.get_header("content-type") == "application/json" then
      opa_input.request.http.parsed_body = kong.request.get_body("application/json")
  end
  if plugin_conf.include_uri_captures_in_opa_input then
    opa_input.request.http.uri_captures = kong.request.get_uri_captures() or EMPTY
  end

  return cjson.encode({ input = opa_input })
end


local function opa_request(opa_input, plugin_conf)
  local httpc = http.new()
  httpc:set_timeout(60000)

  local opa_conn_options = {
    scheme = plugin_conf.opa_protocol,
    host = plugin_conf.opa_host,
    port = plugin_conf.opa_port,
    ssl_verify = plugin_conf.ssl_verify,
  }

  local ok, err = httpc:connect(opa_conn_options)
  if not ok then
    return nil, "failed to connect to OPA server(" .. plugin_conf.opa_host ..
                  ":" .. plugin_conf.opa_port .. "): " .. err
  end

  local request = {
    method = "POST",
    path = plugin_conf.opa_path,
    body = opa_input,
    headers = {
      ["content-type"] = "application/json",
    }
  }

  local res, err = httpc:request(request)
  if not res then
    return nil, "failed to send request to OPA server: " .. err
  end

  if res.status ~= 200 then
    return nil, "received unexpected HTTP response from OPA server: " .. res.status
  end

  local body, err = res:read_body()
  if not body then
    return nil, "failed to read response from OPA server: " .. err
  end

  local ok, err = httpc:set_keepalive(60000)
  if not ok then
    return nil, "failed to set keepalive: " .. err
  end
  return cjson.decode(body)
end


function OpaHandler:access(plugin_conf)
  local err_500_msg = { message = "An unexpected error occurred" }

  -- build input OPA
  local opa_input = build_opa_input(plugin_conf)
  if not opa_input then
    kong.log.err("failed to build OPA input request")
    return kong.response.exit(500, err_500_msg)
  end

  -- make the request to OPA
  local start_time = ngx.now()
  local response, err = opa_request(opa_input, plugin_conf)
  local end_time = ngx.now()
  if err then
    kong.log.err("failed to get decision from OPA: " .. err)
    return kong.response.exit(500, err_500_msg)
  end

  local opa_latency = (end_time - start_time) * 1000
  kong.log.debug("request to OPA took " .. opa_latency .. " ms")

  local allow, response, err = decision.process_decision(response)
  if err then
    kong.log.err("failed to decode process OPA decision: " .. err)
    return kong.response.exit(500, err_500_msg)
  end

  if allow then
    -- let request through
    -- inject headers if any
    local headers = response and response.headers
    if headers then
      kong.service.request.set_headers(headers)
    end

  else
    -- reject request
    local status = response and response.status or 403
    local headers = response and response.headers
    local message = response and response.message or "unauthorized"

    kong.response.exit(status, { ["message"] = message }, headers)
  end
end


return OpaHandler
