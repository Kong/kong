local _M = {}

function _M.serialize(ngx)
  local authenticated_entity
  local ctx = ngx.ctx
  if ctx.authenticated_credential ~= nil then
    authenticated_entity = {
      id = ctx.authenticated_credential.id,
      consumer_id = ctx.authenticated_credential.consumer_id,
    }
    if ctx.authenticated_consumer ~= nil then
      authenticated_entity.custom_id = ctx.authenticated_consumer.custom_id
      authenticated_entity.username = ctx.authenticated_consumer.username
    end
  end

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
    latencies = {
      kong = (ctx.KONG_ACCESS_TIME or 0) +
             (ctx.KONG_RECEIVE_TIME or 0),
      proxy = ctx.KONG_WAITING_TIME or -1,
      request = ngx.var.request_time * 1000
    },
    authenticated_entity = authenticated_entity,
    api = ctx.api,
    client_ip = ngx.var.remote_addr,
    started_at = ngx.req.start_time() * 1000
  }
end

return _M
