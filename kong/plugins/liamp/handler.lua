-- Copyright (C) Kong Inc.

-- Grab pluginname from module name
local plugin_name = ({...})[1]:match("^kong%.plugins%.([^%.]+)")

local BasePlugin = require "kong.plugins.base_plugin"
local responses = require "kong.tools.responses"
local utils = require "kong.tools.utils"
local http = require "resty.http"
local cjson = require "cjson.safe"
local public_utils = require "kong.tools.public"
local singletons = require "kong.singletons"
local constants = require "kong.constants"
local meta = require "kong.meta"

local aws_v4 = require("kong.plugins." .. plugin_name .. ".v4")

local fetch_credentials
do
  -- check if ECS is configured, if so, use it for fetching credentials
  fetch_credentials = require("kong.plugins." .. plugin_name .. ".iam-ecs-credentials")
  if not fetch_credentials.configured then
    -- not set, so fall back on EC2 credentials
    fetch_credentials = require("kong.plugins." .. plugin_name .. ".iam-ec2-credentials")
  end
end

local tostring             = tostring
local tonumber             = tonumber
local pairs                = pairs
local type                 = type
local fmt                  = string.format
local ngx                  = ngx
local ngx_req_read_body    = ngx.req.read_body
local ngx_req_get_uri_args = ngx.req.get_uri_args
local ngx_req_get_headers  = ngx.req.get_headers
local ngx_encode_base64    = ngx.encode_base64
local ngx_update_time      = ngx.update_time
local ngx_now              = ngx.now

local DEFAULT_CACHE_IAM_INSTANCE_CREDS_DURATION = 60
local IAM_CREDENTIALS_CACHE_KEY = "plugin." .. plugin_name .. ".iam_role_temp_creds"
local LOG_PREFIX = "[" .. plugin_name .. "] "


local new_tab
do
  local ok
  ok, new_tab = pcall(require, "table.new")
  if not ok then
    new_tab = function(narr, nrec) return {} end
  end
end


local server_header_value
local server_header_name
local response_bad_gateway
local AWS_PORT = 443


local function get_now()
  ngx_update_time()
  return ngx_now() * 1000 -- time is kept in seconds with millisecond resolution.
end


--[[
  Response format should be
  {
      "statusCode": httpStatusCode,
      "headers": { "headerName": "headerValue", ... },
      "body": "..."
  }
--]]
local function validate_custom_response(response)
  if type(response.statusCode) ~= "number" then
    return nil, "statusCode must be a number"
  end

  if response.headers ~= nil and type(response.headers) ~= "table" then
    return nil, "headers must be a table"
  end

  if response.body ~= nil and type(response.body) ~= "string" then
    return nil, "body must be a string"
  end

  return true
end


local function extract_proxy_response(content)
  local serialized_content, err = cjson.decode(content)
  if not serialized_content then
    return nil, err
  end

  local ok, err = validate_custom_response(serialized_content)
  if not ok then
    return nil, err
  end

  local headers = serialized_content.headers or {}
  local body = serialized_content.body or ""
  headers["Content-Length"] = #body

  return {
    status_code = tonumber(serialized_content.statusCode),
    body = body,
    headers = headers,
  }
end


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

  if server_header_value then
    ngx.header[server_header_name] = server_header_value
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
  AWSLambdaHandler.super.new(self, plugin_name)
end


function AWSLambdaHandler:init_worker()

  if singletons.configuration.enabled_headers then
    -- newer `headers` config directive (0.14.x +)
    if singletons.configuration.enabled_headers[constants.HEADERS.VIA] then
      server_header_value = meta._SERVER_TOKENS
      server_header_name = constants.HEADERS.VIA
    else
      server_header_value = nil
      server_header_name = nil
    end

  else
    -- old `server_tokens` config directive (up to 0.13.x)
    if singletons.configuration.server_tokens then
      server_header_value = _KONG._NAME .. "/" .. _KONG._VERSION
      server_header_name = "Via"
    else
      server_header_value = nil
      server_header_name = nil
    end
  end


  -- response for BAD_GATEWAY was added in 0.14x
  response_bad_gateway = responses.send_HTTP_BAD_GATEWAY
  if not response_bad_gateway then
    response_bad_gateway = function(msg)
      ngx.log(ngx.ERR, LOG_PREFIX, msg)
      return responses.send(502, "Bad Gateway")
    end
  end
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
    ngx.log(ngx.ERR, LOG_PREFIX, "could not JSON encode upstream body",
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
    query = conf.qualifier and "Qualifier=" .. conf.qualifier
  }

  if (not conf.aws_key) or conf.aws_key == "" then
    -- no credentials provided, so try the IAM metadata service
    local iam_role_credentials, err = singletons.cache:get(
      IAM_CREDENTIALS_CACHE_KEY,
      {
        ttl = DEFAULT_CACHE_IAM_INSTANCE_CREDS_DURATION
      },
      fetch_credentials
    )

    if not iam_role_credentials then
      return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
    end

    opts.access_key = iam_role_credentials.access_key
    opts.secret_key = iam_role_credentials.secret_key
    opts.headers["X-Amz-Security-Token"] = iam_role_credentials.session_token

  else
    opts.access_key = conf.aws_key
    opts.secret_key = conf.aws_secret
  end

  local request
  request, err = aws_v4(opts)
  if err then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  end

  -- Trigger request
  local client = http.new()
  client:set_timeout(conf.timeout)

  local kong_wait_time_start = get_now()

  local ok
  if conf.proxy_url then
    ok, err = client:connect_proxy(conf.proxy_url, conf.proxy_scheme, host, port)
  else
    ok, err = client:connect(host, port)
  end
  if not ok then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  end

  ok, err = client:ssl_handshake()
  if not ok then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  end

  local res
  res, err = client:request {
    method = "POST",
    path = request.url,
    body = request.body,
    headers = request.headers
  }
  if not res then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  end

  local content = res:read_body()

  -- setting the latency here is a bit tricky, but because we are not
  -- actually proxying, it will not be overwritten
  ngx.ctx.KONG_WAITING_TIME = get_now() - kong_wait_time_start
  local headers = res.headers

  ok, err = client:set_keepalive(conf.keepalive)
  if not ok then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  end

  local status
  if conf.is_proxy_integration then
    local proxy_response, err = extract_proxy_response(content)
    if not proxy_response then
      return response_bad_gateway("could not JSON decode Lambda function " ..
                                  "response: " .. tostring(err))
    end

    status = proxy_response.status_code
    headers = utils.table_merge(headers, proxy_response.headers)
    content = proxy_response.body
  end

  if not status then
    if conf.unhandled_status
      and headers["X-Amz-Function-Error"] == "Unhandled"
    then
      status = conf.unhandled_status

    else
      status = res.status
    end
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
