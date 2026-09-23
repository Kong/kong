local nkeys = require "table.nkeys"


local kong = kong
local ngx = ngx



local function get_response_headers(n)
  local headers = {}

  for i = 1, n - 2 do
    headers["a" .. i] = "v" .. i
  end

  --headers["content-length"] = "0" (added by nginx/kong)
  --headers["connection"] = "keep-alive" (added by nginx/kong)

  return headers
end


local MaxArgsHandler = {
  VERSION = "0.1-t",
  PRIORITY = 1000,
}


function MaxArgsHandler:access(conf)
  local client_args_count = nkeys(ngx.req.get_uri_args(0))

  ngx.req.read_body()

  kong.ctx.plugin.data = {
    client_args_count = client_args_count,
    kong = {
      request_headers = kong.request.get_headers(),
      uri_args = kong.request.get_query(),
      post_args = kong.request.get_body() or {},
    },
    ngx = {
      request_headers = ngx.req.get_headers(),
      uri_args = ngx.req.get_uri_args(),
      post_args = ngx.req.get_post_args(),
    },
  }

  return kong.response.exit(200, "", get_response_headers(client_args_count))
end


function MaxArgsHandler:header_filter(conf)
  local data = kong.ctx.plugin.data
  return kong.response.exit(200, {
    client_args_count = data.client_args_count,
    kong = {
      request_headers = data.kong.request_headers,
      response_headers = kong.response.get_headers(),
      uri_args = data.kong.uri_args,
      post_args = data.kong.post_args,
    },
    ngx = {
      request_headers = data.ngx.request_headers,
      response_headers = ngx.resp.get_headers(),
      uri_args = data.ngx.uri_args,
      post_args = data.ngx.post_args,
    }
  })
end


return MaxArgsHandler
