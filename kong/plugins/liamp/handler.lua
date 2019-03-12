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

local aws_v4 = require "kong.plugins." .. plugin_name .. ".v4"
local fetch_iam_credentials_from_metadata_service = require "kong.plugins." .. plugin_name .. ".iam-role-credentials"

local tostring             = tostring
local ngx_req_read_body    = ngx.req.read_body
local ngx_req_get_uri_args = ngx.req.get_uri_args
local ngx_req_get_headers  = ngx.req.get_headers
local ngx_encode_base64    = ngx.encode_base64

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

local AWS_PORT = 443

local AWSLambdaHandler = BasePlugin:extend()

function AWSLambdaHandler:new()
  AWSLambdaHandler.super.new(self, plugin_name)
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

  local host = string.format("lambda.%s.amazonaws.com", conf.aws_region)
  local path = string.format("/2015-03-31/functions/%s/invocations",
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

  if conf.use_ec2_iam_role then
    local iam_role_credentials, err = singletons.cache:get(
      IAM_CREDENTIALS_CACHE_KEY,
      {
        ttl = DEFAULT_CACHE_IAM_INSTANCE_CREDS_DURATION
      },
      fetch_iam_credentials_from_metadata_service
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

  local body = res:read_body()
  local headers = res.headers

  ok, err = client:set_keepalive(conf.keepalive)
  if not ok then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  end

  if conf.unhandled_status
     and headers["X-Amz-Function-Error"] == "Unhandled"
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
AWSLambdaHandler.VERSION = "0.1.0"

return AWSLambdaHandler
