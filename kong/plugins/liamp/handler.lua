-- Copyright (C) Kong Inc.

local aws_v4 = require "kong.plugins.liamp.v4"
local aws_serializer = require "kong.plugins.liamp.aws-serializer"
local http = require "resty.http"
local cjson = require "cjson.safe"
local meta = require "kong.meta"
local constants = require "kong.constants"


local fetch_credentials
do
  local credential_sources = {
    require "kong.plugins.liamp.iam-ecs-credentials",
    -- The EC2 one will always return `configured == true`, so must be the last!
    require "kong.plugins.liamp.iam-ec2-credentials",
  }

  for _, credential_source in ipairs(credential_sources) do
    if credential_source.configured then
      fetch_credentials = credential_source.fetchCredentials
      break
    end
  end
end


local tostring             = tostring
local tonumber             = tonumber
local type                 = type
local fmt                  = string.format
local ngx_encode_base64    = ngx.encode_base64
local ngx_update_time      = ngx.update_time
local ngx_now              = ngx.now

local IAM_CREDENTIALS_CACHE_KEY = "plugin.liamp.iam_role_temp_creds"


local server_header_value
local server_header_name
local AWS_PORT = 443


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


local AWSLambdaHandler = {}


local function send(status, content, headers)
  headers = kong.table.merge(headers) -- create a copy of headers

  if server_header_value then
    headers[server_header_name] = server_header_value
  end

  return kong.response.exit(status, content, headers)
end


function AWSLambdaHandler:init_worker()
  if kong.configuration.enabled_headers[constants.HEADERS.VIA] then
    server_header_value = meta._SERVER_TOKENS
    server_header_name = constants.HEADERS.VIA
  else
    server_header_value = nil
    server_header_name = nil
  end
end


function AWSLambdaHandler:access(conf)
  local upstream_body = kong.table.new(0, 6)
  local var = ngx.var

  if conf.awsgateway_compatible then
    upstream_body = aws_serializer(ngx.ctx, conf)

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
      local path = kong.request.get_path()
      local query = kong.request.get_raw_query()
      if query ~= "" then
        upstream_body.request_uri = path .. "?" .. query
      else
        upstream_body.request_uri = path
      end
      upstream_body.request_uri_args = kong.request.get_query()
    end

    if conf.forward_request_body then
      local content_type = kong.request.get_header("content-type")
      local body_raw = kong.request.get_raw_body()
      local body_args, err = kong.request.get_body()
      if err and err:match("content type") then
        body_args = {}
        if not raw_content_types[content_type] then
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

  if not conf.aws_key then
    -- no credentials provided, so try the IAM metadata service
    local iam_role_credentials, err = kong.cache:get(
      IAM_CREDENTIALS_CACHE_KEY,
      nil,
      fetch_credentials
    )

    if not iam_role_credentials then
      return kong.response.exit(500, {
        message = "An unexpected error occurred"
      })
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
    kong.log.err(err)
    return kong.response.exit(500, { message = "An unexpected error occurred" })
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
    kong.log.err(err)
    return kong.response.exit(500, { message = "An unexpected error occurred" })
  end

  ok, err = client:ssl_handshake()
  if not ok then
    kong.log.err(err)
    return kong.response.exit(500, { message = "An unexpected error occurred" })
  end

  local res
  res, err = client:request {
    method = "POST",
    path = request.url,
    body = request.body,
    headers = request.headers
  }
  if not res then
    kong.log.err(err)
    return kong.response.exit(500, { message = "An unexpected error occurred" })
  end

  local content = res:read_body()

  -- setting the latency here is a bit tricky, but because we are not
  -- actually proxying, it will not be overwritten
  ngx.ctx.KONG_WAITING_TIME = get_now() - kong_wait_time_start
  local headers = res.headers

  if var.http2 then
    headers["Connection"] = nil
    headers["Keep-Alive"] = nil
    headers["Proxy-Connection"] = nil
    headers["Upgrade"] = nil
    headers["Transfer-Encoding"] = nil
  end

  if conf.proxy_url then
    client:close()
  else
    ok, err = client:set_keepalive(conf.keepalive)
    if not ok then
      kong.log.err(err)
      return kong.response.exit(500, { message = "An unexpected error occurred" })
    end
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


  return send(status, content, headers)
end

AWSLambdaHandler.PRIORITY = 750
AWSLambdaHandler.VERSION = "0.2.0"

return AWSLambdaHandler
