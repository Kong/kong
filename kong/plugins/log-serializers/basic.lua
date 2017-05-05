local _M = {}

function _M.serialize(ngx)
  local authenticated_entity
  if ngx.ctx.authenticated_credential ~= nil then
    authenticated_entity = {
      id = ngx.ctx.authenticated_credential.id,
      consumer_id = ngx.ctx.authenticated_credential.consumer_id
    }
  end
  
  local addr = ngx.ctx.balancer_address

  return {
    request = {
      uri = ngx.var.request_uri,
      request_uri = ngx.var.scheme.."://"..ngx.var.host..":"..ngx.var.server_port..ngx.var.request_uri,
      querystring = ngx.req.get_uri_args(), -- parameters, as a table
      method = ngx.req.get_method(), -- http method
      headers = ngx.req.get_headers(),
      size = ngx.var.request_length
    },
    response = {
      status = ngx.status,
      headers = ngx.resp.get_headers(),
      size = ngx.var.bytes_sent
    },
    tries = addr.tries,
    latencies = {
      kong = (ngx.ctx.KONG_ACCESS_TIME or 0) +
             (ngx.ctx.KONG_RECEIVE_TIME or 0) +
             (ngx.ctx.KONG_REWRITE_TIME or 0),
      proxy = ngx.ctx.KONG_WAITING_TIME or -1,
      request = ngx.var.request_time * 1000
    },
    authenticated_entity = authenticated_entity,
    api = ngx.ctx.api,
    consumer = ngx.ctx.authenticated_consumer,
    client_ip = ngx.var.remote_addr,
    started_at = ngx.req.start_time() * 1000
  }
end

return _M
