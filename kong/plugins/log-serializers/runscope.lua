local ngx_now = ngx.now
local req_get_method = ngx.req.get_method
local req_start_time = ngx.req.start_time
local req_get_headers = ngx.req.get_headers
local res_get_headers = ngx.resp.get_headers

local _M = {}

function _M.serialize(ngx)
  local runscope_ctx = ngx.ctx.runscope or {}

  return {
    request = {
      url = ngx.var.scheme.."://"..ngx.var.host..":"..ngx.var.server_port..ngx.var.request_uri,
      method = req_get_method(),
      headers = req_get_headers(),
      body = runscope_ctx.req_body,
      timestamp = req_start_time(),
      form = runscope_ctx.req_post_args
    },
    response = {
      status = ngx.status,
      headers = res_get_headers(),
      size_bytes = ngx.var.body_bytes_sent,
      body = runscope_ctx.res_body,
      timestamp = ngx_now(),
      response_time = ngx.var.request_time * 1
    }
  }
end

return _M
