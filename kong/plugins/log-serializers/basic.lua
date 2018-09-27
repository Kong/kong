local tablex = require "pl.tablex"

local _M = {}

local EMPTY = tablex.readonly({})

function _M.serialize(ngx)
  local ctx = ngx.ctx
  local var = ngx.var
  local req = ngx.req
  local proxy_request_state = ctx.proxy_request_state or EMPTY
  local routing = proxy_request_state.routing or EMPTY

  local authenticated_entity
  if ctx.authenticated_credential ~= nil then
    authenticated_entity = {
      id = ctx.authenticated_credential.id,
      consumer_id = ctx.authenticated_credential.consumer_id
    }
  end

  local request_uri = var.request_uri or ""

  return {
    request = {
      uri = request_uri,
      url = var.scheme .. "://" .. var.host .. ":" .. var.server_port .. request_uri,
      querystring = req.get_uri_args(), -- parameters, as a table
      method = req.get_method(), -- http method
      headers = req.get_headers(),
      size = var.request_length
    },
    upstream_uri = var.upstream_uri,
    response = {
      status = ngx.status,
      headers = ngx.resp.get_headers(),
      size = var.bytes_sent
    },
    tries = ((ctx.proxy_request_state or EMPTY).proxy or EMPTY).try_data,
    latencies = {
      kong = (ctx.KONG_ACCESS_TIME or 0) +
             (ctx.KONG_RECEIVE_TIME or 0) +
             (ctx.KONG_REWRITE_TIME or 0) +
             (ctx.KONG_BALANCER_TIME or 0),
      proxy = ctx.KONG_WAITING_TIME or -1,
      request = var.request_time * 1000
    },
    authenticated_entity = authenticated_entity,
    route = routing.route,
    service = routing.service,
    api = routing.api,
    consumer = ctx.authenticated_consumer,
    client_ip = var.remote_addr,
    started_at = req.start_time() * 1000
  }
end

return _M
