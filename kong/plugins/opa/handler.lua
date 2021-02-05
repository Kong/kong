local ngx_ssl = require "ngx.ssl"
local cjson = require "cjson"
local http = require "resty.http"
local decision = require "kong.plugins.opa.decision"
local ngx = ngx
local kong = kong


local OpaHandler = {
  -- execute logic in opa after auth plugins have run but before
  -- rate-limiting and any transformations run
  PRIORITY = 920,
  VERSION = "0.1.0",
}


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
    opa_input.service = nctx.route
  end
  if plugin_conf.include_consumer_in_opa_input then
    opa_input.service = nctx.consumer
  end

  return cjson.encode({ input = opa_input })
end


local function opa_request(opa_input, plugin_conf)
  local httpc = http.new()
  httpc:set_timeout(60000)
  local ok, err = httpc:connect(plugin_conf.opa_host, plugin_conf.opa_port)
  if not ok then
    return nil, "failed to connect to OPA server(" .. plugin_conf.opa_host ..
                  ":" .. plugin_conf.opa_port .. "): " .. err
  end
  if plugin_conf.protocol == "https" then
    local _, err = httpc:ssl_handshake(true, plugin_conf.opa_host, true)
    if err then
    return nil, "failed to perform SSL handshake with OPA server(" .. 
                  plugin_conf.opa_host .. ":" .. 
                  plugin_conf.opa_port .. "): " .. err
    end
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
    return nil, "received unexpect HTTP response from OPA server: " .. res.status
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

  -- build input OPA
  local opa_input = build_opa_input(plugin_conf)
  if not opa_input then
    kong.log.error("failed to build request: " .. err)
    return kong.response.exit(500, { message = "An unexpected error occurred" })
  end

  -- make the request to OPA
  local start_time = ngx.now()
  local response, err = opa_request(opa_input, plugin_conf)
  local end_time = ngx.now()
  if err then
    kong.log.err("failed to get decision from OPA: " .. err)
    return kong.response.exit(500, { message = "An unexpected error occurred" })
  end

  local opa_latency = (end_time - start_time) * 1000
  kong.log.debug("request to OPA took " .. opa_latency .. " ms")

  local allow, response, err = decision.process_decision(response)
  if err then
    kong.log.err("failed to decode process OPA decision: " .. err)
    return kong.response.exit(500, { message = "An unexpected error occurred" })
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
    kong.response.exit(status, { message = "unauthorized" }, headers)
  end
end


return OpaHandler
