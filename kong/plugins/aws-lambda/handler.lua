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

local AWS_PORT = 443

local AWSLambdaHandler = BasePlugin:extend()

function AWSLambdaHandler:new()
  AWSLambdaHandler.super.new(self, "aws-lambda")
end

local function retrieve_parameters()
  ngx_req_read_body()

  return utils.table_merge(ngx_req_get_uri_args(), public_utils.get_body_args())
end

function AWSLambdaHandler:access(conf)
  AWSLambdaHandler.super.access(self)

  local bodyJson = cjson.encode(retrieve_parameters())

  local host = string.format("lambda.%s.amazonaws.com", conf.aws_region)
  local path = string.format("/2015-03-31/functions/%s/invocations",
                            conf.function_name)
  local opts = {
    region = conf.aws_region,
    service = "lambda",
    method = "POST",
    headers = {
      ["X-Amz-Target"] = "invoke",
      ["X-Amz-Invocation-Type"] = conf.invocation_type,
      ["X-Amx-Log-Type"] = conf.log_type,
      ["Content-Type"] = "application/x-amz-json-1.1",
      ["Content-Length"] = tostring(#bodyJson)
    },
    body = bodyJson,
    path = path,
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
  client:connect(host, conf.port or AWS_PORT)
  client:set_timeout(conf.timeout)
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
