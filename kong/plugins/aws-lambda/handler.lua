-- Copyright (C) Kong Inc.

local aws_v4 = require "kong.plugins.aws-lambda.v4"
local aws_serializer = require "kong.plugins.aws-lambda.aws-serializer"
local http = require "resty.http"
local cjson = require "cjson.safe"
local meta = require "kong.meta"
local constants = require "kong.constants"
local request_util = require "kong.plugins.aws-lambda.request-util"
local kong = kong

local VIA_HEADER = constants.HEADERS.VIA
local VIA_HEADER_VALUE = meta._NAME .. "/" .. meta._VERSION
local IAM_CREDENTIALS_CACHE_KEY_PATTERN = "plugin.aws-lambda.iam_role_temp_creds.%s"
local AWS_PORT = 443
local AWS_REGION do
  AWS_REGION = os.getenv("AWS_REGION") or os.getenv("AWS_DEFAULT_REGION")
end


local function fetch_aws_credentials(aws_conf)
  local fetch_metadata_credentials do
    local metadata_credentials_source = {
      require "kong.plugins.aws-lambda.iam-ecs-credentials",
      -- The EC2 one will always return `configured == true`, so must be the last!
      require "kong.plugins.aws-lambda.iam-ec2-credentials",
    }

    for _, credential_source in ipairs(metadata_credentials_source) do
      if credential_source.configured then
        fetch_metadata_credentials = credential_source.fetchCredentials
        break
      end
    end
  end

  if aws_conf.aws_assume_role_arn then
    local metadata_credentials, err = fetch_metadata_credentials()

    if err then
      return nil, err
    end

    local aws_sts_cred_source = require "kong.plugins.aws-lambda.iam-sts-credentials"
    return aws_sts_cred_source.fetch_assume_role_credentials(aws_conf.aws_region,
                                                             aws_conf.aws_assume_role_arn,
                                                             aws_conf.aws_role_session_name,
                                                             metadata_credentials.access_key,
                                                             metadata_credentials.secret_key,
                                                             metadata_credentials.session_token)

  else
    return fetch_metadata_credentials()
  end
end


local ngx_encode_base64 = ngx.encode_base64
local ngx_decode_base64 = ngx.decode_base64
local ngx_update_time = ngx.update_time
local tostring = tostring
local tonumber = tonumber
local ngx_now = ngx.now
local ngx_var = ngx.var
local error = error
local pairs = pairs
local kong = kong
local type = type
local fmt = string.format


local raw_content_types = {
  ["text/plain"] = true,
  ["text/html"] = true,
  ["application/xml"] = true,
  ["text/xml"] = true,
  ["application/soap+xml"] = true,
}


local function get_now()
  ngx_update_time()
  return ngx_now() * 1000 -- time is kept in seconds with millisecond resolution.
end


local function validate_http_status_code(status_code)
  if not status_code then
    return false
  end

  if type(status_code) == "string" then
    status_code = tonumber(status_code)

    if not status_code then
      return false
    end
  end

  if status_code >= 100 and status_code <= 599 then
    return status_code
  end

  return false
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
  if not validate_http_status_code(response.statusCode) then
    return nil, "statusCode validation failed"
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
  local isBase64Encoded = serialized_content.isBase64Encoded or false
  if isBase64Encoded then
    body = ngx_decode_base64(body)
  end

  local multiValueHeaders = serialized_content.multiValueHeaders
  if multiValueHeaders then
    for header, values in pairs(multiValueHeaders) do
      headers[header] = values
    end
  end

  headers["Content-Length"] = #body

  return {
    status_code = tonumber(serialized_content.statusCode),
    body = body,
    headers = headers,
  }
end


local AWSLambdaHandler = {}


function AWSLambdaHandler:access(conf)
  local upstream_body = kong.table.new(0, 6)
  local ctx = ngx.ctx

  if conf.awsgateway_compatible then
    upstream_body = aws_serializer(ctx, conf)

  elseif conf.forward_request_body or
    conf.forward_request_headers or
    conf.forward_request_method or
    conf.forward_request_uri then

    -- new behavior to forward request method, body, uri and their args
    if conf.forward_request_method then
      upstream_body.request_method = kong.request.get_method()
    end

    if conf.forward_request_headers then
      upstream_body.request_headers = kong.request.get_headers()
    end

    if conf.forward_request_uri then
      upstream_body.request_uri = kong.request.get_path_with_query()
      upstream_body.request_uri_args = kong.request.get_query()
    end

    if conf.forward_request_body then
      local content_type = kong.request.get_header("content-type")
      local body_raw = request_util.read_request_body(conf.skip_large_bodies)
      local body_args, err = kong.request.get_body()
      if err and err:match("content type") then
        body_args = {}
        if not raw_content_types[content_type] and conf.base64_encode_body then
          -- don't know what this body MIME type is, base64 it just in case
          body_raw = ngx_encode_base64(body_raw)
          upstream_body.request_body_base64 = true
        end
      end

      upstream_body.request_body      = body_raw
      upstream_body.request_body_args = body_args
    end

  else
    -- backwards compatible upstream body for configurations not specifying
    -- `forward_request_*` values
    local body_args = kong.request.get_body()
    upstream_body = kong.table.merge(kong.request.get_query(), body_args)
  end

  local upstream_body_json, err = cjson.encode(upstream_body)
  if not upstream_body_json then
    kong.log.err("could not JSON encode upstream body",
                 " to forward request values: ", err)
  end

  local region = conf.aws_region or AWS_REGION
  local host = conf.host

  if not region then
    return error("no region specified")
  end

  if not host then
    host = fmt("lambda.%s.amazonaws.com", region)
  end

  local path = fmt("/2015-03-31/functions/%s/invocations", conf.function_name)
  local port = conf.port or AWS_PORT

  local opts = {
    region = region,
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

  local aws_conf = {
    aws_region = conf.aws_region,
    aws_assume_role_arn = conf.aws_assume_role_arn,
    aws_role_session_name = conf.aws_role_session_name,
  }

  if not conf.aws_key then
    -- no credentials provided, so try the IAM metadata service
    local iam_role_cred_cache_key = fmt(IAM_CREDENTIALS_CACHE_KEY_PATTERN, conf.aws_assume_role_arn or "default")
    local iam_role_credentials = kong.cache:get(
      iam_role_cred_cache_key,
      nil,
      fetch_aws_credentials,
      aws_conf
    )

    if not iam_role_credentials then
      return kong.response.error(500)
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
    return error(err)
  end

  local uri = port and fmt("https://%s:%d", host, port)
                    or fmt("https://%s", host)

  local proxy_opts
  if conf.proxy_url then
    -- lua-resty-http uses the request scheme to determine which of
    -- http_proxy/https_proxy it will use, and from this plugin's POV, the
    -- request scheme is always https
    proxy_opts = { https_proxy = conf.proxy_url }
  end

  -- Trigger request
  local client = http.new()
  client:set_timeout(conf.timeout)
  local kong_wait_time_start = get_now()
  local res, err = client:request_uri(uri, {
    method = "POST",
    path = request.url,
    body = request.body,
    headers = request.headers,
    ssl_verify = false,
    proxy_opts = proxy_opts,
    keepalive_timeout = conf.keepalive,
  })
  if not res then
    return error(err)
  end

  local content = res.body

  if res.status >= 400 then
    return error(content)
  end

  -- setting the latency here is a bit tricky, but because we are not
  -- actually proxying, it will not be overwritten
  ctx.KONG_WAITING_TIME = get_now() - kong_wait_time_start
  local headers = res.headers

  if ngx_var.http2 then
    headers["Connection"] = nil
    headers["Keep-Alive"] = nil
    headers["Proxy-Connection"] = nil
    headers["Upgrade"] = nil
    headers["Transfer-Encoding"] = nil
  end

  local status

  if conf.is_proxy_integration then
    local proxy_response, err = extract_proxy_response(content)
    if not proxy_response then
      kong.log.err(err)
      return kong.response.exit(502, { message = "Bad Gateway",
                                       error = "could not JSON decode Lambda " ..
                                         "function response: " .. err })
    end

    status = proxy_response.status_code
    headers = kong.table.merge(headers, proxy_response.headers)
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

  headers = kong.table.merge(headers) -- create a copy of headers

  if kong.configuration.enabled_headers[VIA_HEADER] then
    headers[VIA_HEADER] = VIA_HEADER_VALUE
  end

  return kong.response.exit(status, content, headers)
end

AWSLambdaHandler.PRIORITY = 750
AWSLambdaHandler.VERSION = meta.version

return AWSLambdaHandler
