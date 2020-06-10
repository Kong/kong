local tablex = require "pl.tablex"
local ngx_ssl = require "ngx.ssl"
local gkong = kong

local _M = {}

local EMPTY = tablex.readonly({})
local REDACTED_REQUEST_HEADERS = { "authorization", "proxy-authorization" }
local REDACTED_RESPONSE_HEADERS = {}

function _M.serialize(ngx, kong)
  local ctx = ngx.ctx
  local var = ngx.var
  local req = ngx.req

  if not kong then
    kong = gkong
  end

  local authenticated_entity
  if ctx.authenticated_credential ~= nil then
    authenticated_entity = {
      id = ctx.authenticated_credential.id,
      consumer_id = ctx.authenticated_credential.consumer_id
    }
  end

  local request_tls
  local request_tls_ver = ngx_ssl.get_tls1_version_str()
  if request_tls_ver then
    request_tls = {
      version = request_tls_ver,
      cipher = var.ssl_cipher,
      client_verify = var.ssl_client_verify,
    }
  end

  local request_uri = var.request_uri or ""

  local req_headers = kong.request.get_headers()
  for _, header in ipairs(REDACTED_REQUEST_HEADERS) do
    if req_headers[header] then
      req_headers[header] = "REDACTED"
    end
  end

  local resp_headers = ngx.resp.get_headers()
  for _, header in ipairs(REDACTED_RESPONSE_HEADERS) do
    if resp_headers[header] then
      resp_headers[header] = "REDACTED"
    end
  end

  local host_port = ctx.host_port or var.server_port

  return {
    request = {
      uri = request_uri,
      url = var.scheme .. "://" .. var.host .. ":" .. host_port .. request_uri,
      querystring = kong.request.get_query(), -- parameters, as a table
      method = kong.request.get_method(), -- http method
      headers = req_headers,
      size = var.request_length,
      tls = request_tls
    },
    upstream_uri = var.upstream_uri,
    response = {
      status = ngx.status,
      headers = resp_headers,
      size = var.bytes_sent
    },
    tries = (ctx.balancer_data or EMPTY).tries,
    latencies = {
      kong = (ctx.KONG_ACCESS_TIME or 0) +
             (ctx.KONG_RECEIVE_TIME or 0) +
             (ctx.KONG_REWRITE_TIME or 0) +
             (ctx.KONG_BALANCER_TIME or 0),
      proxy = ctx.KONG_WAITING_TIME or -1,
      request = var.request_time * 1000
    },
    authenticated_entity = authenticated_entity,
    route = ctx.route,
    service = ctx.service,
    consumer = ctx.authenticated_consumer,
    client_ip = var.remote_addr,
    started_at = req.start_time() * 1000
  }
end

return _M
