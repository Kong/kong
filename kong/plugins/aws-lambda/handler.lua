-- Copyright (C) Mashape, Inc.

local BasePlugin = require "kong.plugins.base_plugin"
local aws_v4 = require "kong.plugins.aws-lambda.v4"
local responses = require "kong.tools.responses"
local utils = require "kong.tools.utils"
local http = require "resty.http"
local cjson = require "cjson.safe"
local public_utils = require "kong.tools.public"

local ngx_req_read_body = ngx.req.read_body
local ngx_req_get_uri_args = ngx.req.get_uri_args
local ngx_req_get_body_data = ngx.req.get_body_data
local ngx_req_get_headers = ngx.req.get_headers
local ngx_encode_base64 = ngx.encode_base64

local string_find = string.find

local AWS_PORT = 443

local AWSLambdaHandler = BasePlugin:extend()

function AWSLambdaHandler:new()
  AWSLambdaHandler.super.new(self, "aws-lambda")
end

local function retrieve_body(content_type)
  local raw_body = ngx_req_get_body_data()
  if not raw_body then
    return nil
  end

  if content_type then
    if string_find(content_type, "application/json", nil, true) then
      local body_json, err = cjson.decode(raw_body)
      if not body_json then
          ngx.log(ngx.ERR, "[aws-lambda] could not encode JSON ",
                  "body for forwarded request body: ", err)
      end
      return body_json
    elseif ( string_find(content_type, "application/xml", nil, true)
             or  string_find(content_type, "application/soap+xml", nil, true)
             or  string_find(content_type, "text/", nil, true) )
    then
       return raw_body
    end
  end
  return ngx_encode_base64(raw_body)
end

function AWSLambdaHandler:access(conf)
  AWSLambdaHandler.super.access(self)

  ngx_req_read_body()

  local upstream_body

  if conf.forward_request_body or conf.forward_http_headers
     or conf.forward_http_method or conf.forward_request_uri then
     local var = ngx.var
     upstream_body = {
       request_body_args = not conf.forward_request_body and public_utils.get_body_args() or nil,
       request_uri_args = not conf.forward_request_uri and ngx_req_get_uri_args() or nil,
       request_body = conf.forward_request_body and retrieve_body(var.http_content_type) or nil,
       request_http_headers = conf.forward_request_http_headers and ngx_req_get_headers() or nil,
       request_http_method = conf.forward_request_http_method and var.request_method or nil,
       request_uri = conf.forward_request_uri and var.request_uri or nil
     }
  else
     upstream_body = utils.table_merge(ngx_req_get_uri_args(), public_utils.get_body_args())
  end

  local body_json, err = cjson.encode(upstream_body)
  if not body_json then
    ngx.log(ngx.ERR, "[aws-lambda] could not encode JSON ",
            "body for forwarded request values: ", err)
  end

  local host = string.format("lambda.%s.amazonaws.com", conf.aws_region)
  local path = string.format("/2015-03-31/functions/%s/invocations",
                            conf.function_name)
  local port = conf.aws_port or AWS_PORT

  local opts = {
    region = conf.aws_region,
    service = "lambda",
    method = "POST",
    headers = {
      ["X-Amz-Target"] = "invoke",
      ["X-Amz-Invocation-Type"] = conf.invocation_type,
      ["X-Amx-Log-Type"] = conf.log_type,
      ["Content-Type"] = "application/x-amz-json-1.1",
      ["Content-Length"] = tostring(#body_json)
    },
    body = body_json,
    path = path,
    host = host,
    port = port,
    access_key = conf.aws_key,
    secret_key = conf.aws_secret,
    query = conf.qualifier and "Qualifier="..conf.qualifier
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

  local body = res:read_body()
  local headers = res.headers

  local ok, err = client:set_keepalive(conf.keepalive)
  if not ok then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  end

  if conf.unhandled_status
     and headers["X-Amzn-Function-Error"] == "Unhandled"
  then
    ngx.status = conf.unhandled_status

  else
    ngx.status = res.status
  end

  -- Send response to client
  for k, v in pairs(headers) do
    ngx.header[k] = v
  end

  ngx.say(body)

  return ngx.exit(res.status)
end

AWSLambdaHandler.PRIORITY = 750

return AWSLambdaHandler
