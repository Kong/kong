-- Copyright (C) Kong Inc.
local BasePlugin = require "kong.plugins.base_plugin"
local aws_v4 = require "kong.plugins.aws-lambda.v4"
local singletons = require "kong.singletons"
local responses = require "kong.tools.responses"
local constants = require "kong.constants"
local utils = require "kong.tools.utils"
local meta = require "kong.meta"
local http = require "resty.http"
local cjson = require "cjson.safe"
local public_utils = require "kong.tools.public"


local tostring             = tostring
local pairs                = pairs
local type                 = type
local fmt                  = string.format
local ngx                  = ngx
local ngx_req_read_body    = ngx.req.read_body
local ngx_req_get_uri_args = ngx.req.get_uri_args
local ngx_req_get_headers  = ngx.req.get_headers
local ngx_encode_base64    = ngx.encode_base64


local new_tab
do
  local ok
  ok, new_tab = pcall(require, "table.new")
  if not ok then
    new_tab = function(narr, nrec) return {} end
  end
end


local server_header = meta._SERVER_TOKENS


local AWS_PORT = 443


local function send(status, content, headers)
  ngx.status = status

  if type(headers) == "table" then
    for k, v in pairs(headers) do
      ngx.header[k] = v
    end
  end

  if not ngx.header["Content-Length"] then
    ngx.header["Content-Length"] = #content
  end

  if singletons.configuration.enabled_headers[constants.HEADERS.VIA] then
    ngx.header[constants.HEADERS.VIA] = server_header
  end

  ngx.print(content)

  return ngx.exit(status)
end


local function flush(ctx)
  ctx = ctx or ngx.ctx
  local response = ctx.delayed_response
  return send(response.status_code, response.content, response.headers)
end


local AWSLambdaHandler = BasePlugin:extend()


function AWSLambdaHandler:new()
  AWSLambdaHandler.super.new(self, "aws-lambda")
end


function AWSLambdaHandler:access(conf)
  AWSLambdaHandler.super.access(self)

  local upstream_body = new_tab(0, 6)

  if conf.forward_request_body or conf.forward_request_headers
    or conf.forward_request_method or conf.forward_request_uri
  then
    -- new behavior to forward request method, body, uri and their args
    local var = ngx.var

    if conf.forward_request_method then
      upstream_body.request_method = var.request_method
    end

    if conf.forward_request_headers then
      upstream_body.request_headers = ngx_req_get_headers()
    end

    if conf.forward_request_uri then
      upstream_body.request_uri      = var.request_uri
      upstream_body.request_uri_args = ngx_req_get_uri_args()
    end

    if conf.forward_request_body then
      ngx_req_read_body()

      local body_args, err_code, body_raw = public_utils.get_body_info()
      if err_code == public_utils.req_body_errors.unknown_ct then
        -- don't know what this body MIME type is, base64 it just in case
        body_raw = ngx_encode_base64(body_raw)
        upstream_body.request_body_base64 = true
      end

      upstream_body.request_body      = body_raw
      upstream_body.request_body_args = body_args
    end

  else
    -- backwards compatible upstream body for configurations not specifying
    -- `forward_request_*` values
    ngx_req_read_body()

    local body_args = public_utils.get_body_args()
    upstream_body = utils.table_merge(ngx_req_get_uri_args(), body_args)
  end

  local upstream_body_json, err = cjson.encode(upstream_body)
  if not upstream_body_json then
    ngx.log(ngx.ERR, "[aws-lambda] could not JSON encode upstream body",
                     " to forward request values: ", err)
  end

  local host = fmt("lambda.%s.amazonaws.com", conf.aws_region)
  local path = fmt("/2015-03-31/functions/%s/invocations",
                            conf.function_name)
  local port = conf.port or AWS_PORT

  local opts = {
    region = conf.aws_region,
    service = "lambda",
    method = "POST",
    headers = {
      ["X-Amz-Target"] = "invoke",
      ["X-Amz-Invocation-Type"] = conf.invocation_type,
      ["X-Amz-Log-Type"] = conf.log_type,
      ["Content-Type"] = "application/x-amz-json-1.1",
      ["Content-Length"] = upstream_body_json and tostring(#upstream_body_json),
    },
    body = upstream_body_json,
    path = path,
    host = host,
    port = port,
    access_key = conf.aws_key,
    secret_key = conf.aws_secret,
    query = conf.qualifier and "Qualifier=" .. conf.qualifier
  }

  local request, err = aws_v4(opts)
  if err then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  end

  -- Trigger request
  local client = http.new()
  client:set_timeout(conf.timeout)
  client:connect(host, port)
  local ok, err = client:ssl_handshake()
  if not ok then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  end

  local res, err = client:request {
    method = "POST",
    path = request.url,
    body = request.body,
    headers = request.headers
  }
  if not res then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  end

  local content = res:read_body()
  local headers = res.headers

  local ok, err = client:set_keepalive(conf.keepalive)
  if not ok then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  end

  local status
  if conf.unhandled_status
     and headers["X-Amz-Function-Error"] == "Unhandled"
  then
    status = conf.unhandled_status

  else
    status = res.status
  end

  local ctx = ngx.ctx
  if ctx.delay_response and not ctx.delayed_response then
    ctx.delayed_response = {
      status_code = status,
      content     = content,
      headers     = headers,
    }

    ctx.delayed_response_callback = flush

    return
  end

  return send(status, content, headers)
end


AWSLambdaHandler.PRIORITY = 750
AWSLambdaHandler.VERSION = "0.1.1"


return AWSLambdaHandler
