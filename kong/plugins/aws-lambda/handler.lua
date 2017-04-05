-- Copyright (C) Mashape, Inc.

local BasePlugin = require "kong.plugins.base_plugin"
local aws_v4 = require "kong.plugins.aws-lambda.v4"
local responses = require "kong.tools.responses"
local utils = require "kong.tools.utils"
local Multipart = require "multipart"
local http = require "resty.http"
local cjson = require "cjson.safe"
local public_utils = require "kong.tools.public"

local string_find = string.find
local ngx_req_get_headers = ngx.req.get_headers
local ngx_req_read_body = ngx.req.read_body
local ngx_req_get_uri_args = ngx.req.get_uri_args
local ngx_req_get_body_data = ngx.req.get_body_data

local CONTENT_TYPE = "content-type"

local MOCK_AWS_HOST = 'localhost'
local MOCK_AWS_PORT = 10001
local AWS_PORT = 443

local AWSLambdaHandler = BasePlugin:extend()

function AWSLambdaHandler:new()
  AWSLambdaHandler.super.new(self, "aws-lambda")
end

local function retrieve_parameters()
  ngx_req_read_body()
  local body_parameters, err
  local content_type = ngx_req_get_headers()[CONTENT_TYPE]
  if content_type and string_find(content_type:lower(), "multipart/form-data", nil, true) then
    body_parameters = Multipart(ngx_req_get_body_data(), content_type):get_all()
  elseif content_type and string_find(content_type:lower(), "application/json", nil, true) then
    body_parameters, err = cjson.decode(ngx_req_get_body_data())
    if err then
      body_parameters = {}
    end
  else
    body_parameters = public_utils.get_post_args()
  end

  return utils.table_merge(ngx_req_get_uri_args(), body_parameters)
end

function AWSLambdaHandler:access(conf)
  AWSLambdaHandler.super.access(self)

  local bodyJson = cjson.encode(retrieve_parameters())

  local host, path, port

  if conf.aws_region ~= 'mock' then
    host = string.format("lambda.%s.amazonaws.com", conf.aws_region)
    port = AWS_PORT

  else
    host = MOCK_AWS_HOST
    port = MOCK_AWS_PORT
  end

  path = string.format("/2015-03-31/functions/%s/invocations",
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
    query = conf.qualifier and "Qualifier="..conf.qualifier
  }

  local request, err = aws_v4(opts)
  if err then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  end

  -- Trigger request
  local client = http.new()
  client:connect(host, port)
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

  ngx.status = res.status

  -- Send response to client
  for k, v in pairs(headers) do
    ngx.header[k] = v
  end

  ngx.say(body)

  return ngx.exit(res.status)
end

AWSLambdaHandler.PRIORITY = 750

return AWSLambdaHandler
