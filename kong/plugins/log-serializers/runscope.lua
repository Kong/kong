local _M = {}

function _M.serialize(ngx)
  
  -- JSON format below based on Runscope Messages resource:
  -- https://www.runscope.com/docs/api/messages#message-create
  -- Not sent: req/res:body_encoding, req:form, res:reason

  -- timers
  -- @see core.handler for their definition
  local req_send_time = ngx.ctx.KONG_PROXY_LATENCY or -1
  local req_wait_time = ngx.ctx.KONG_WAITING_TIME or -1
  local req_receive_time = ngx.ctx.KONG_RECEIVE_TIME or -1

  -- Compute the total time. If some properties were unavailable
  -- (because the proxying was aborted), then don't add the value.
  local req_time = 0
  for _, timer in ipairs({req_send_time, req_wait_time, req_receive_time}) do
    if timer > 0 then
      req_time = req_time + timer
    end
  end
  return {
    request = {
      url = ngx.var.scheme.."://"..ngx.var.host..":"..ngx.var.server_port..ngx.var.request_uri,
      method = ngx.req.get_method(),
      headers = ngx.req.get_headers(),
      body = ngx.ctx.runscope.req_body
    },
    response = {
      status = ngx.status,
      headers = ngx.resp.get_headers(),
      size_bytes = ngx.var.bytes_sent,
      body = ngx.ctx.runscope.res_body,
      timestamp = ngx.req_start_time,
      response_time = req_time / 1000
    }
  }
end

return _M
