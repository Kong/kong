local _M = {}

function _M.serialize(ngx)
  local authenticated_entity
  if ngx.ctx.authenticated_credential ~= nil then

  end

  return {
    tag = {
      uri = ngx.var.request_uri,
      request_uri = ngx.var.scheme.."://"..ngx.var.host..":"..ngx.var.server_port..ngx.var.request_uri,
      request_querystring = ngx.req.get_uri_args(), -- parameters, as a table
      request_method = ngx.req.get_method(), -- http method
      request_headers = ngx.req.get_headers(),
      response_headers = ngx.resp.get_headers(),
      client_ip = ngx.var.remote_addr,
      api = ngx.ctx.api,
      authenticated_entity_id = ngx.ctx.authenticated_credential and ngx.ctx.authenticated_credential.id,
      authenticated_entity_consumer_id = ngx.ctx.authenticated_credential and ngx.ctx.authenticated_credential.consumer_id
    },
    field = {
      request_size = ngx.var.request_length,
      response_status = ngx.status,
      response_size = ngx.var.bytes_sent,
      latencies_kong = (ngx.ctx.KONG_ACCESS_TIME or 0) +
               (ngx.ctx.KONG_RECEIVE_TIME or 0),
      latencies_proxy = ngx.ctx.KONG_WAITING_TIME or -1,
      latencies_request = ngx.var.request_time * 1000,
      started_at = ngx.req.start_time() * 1000
    }
  }
end

return _M
