-- Copyright (C) Kong Inc.

local fmt = string.format
local ngx_var = ngx.var
local ngx_now = ngx.now
local ngx_update_time = ngx.update_time
local kong = kong

local meta = require "kong.meta"
local constants = require "kong.constants"
local VIA_HEADER = constants.HEADERS.VIA
local VIA_HEADER_VALUE = meta._NAME .. "/" .. meta._VERSION

local request_util = require "kong.plugins.aws-lambda.request-util"
local build_request_payload = request_util.build_request_payload
local extract_proxy_response = request_util.extract_proxy_response

local aws = require("resty.aws")
-- Loading necessary runtime env vars but avoid region fetching from IMDS
-- Since this happens inside `require`
local _ = require("resty.aws.config").get_config()
local AWS_REGION do
  AWS_REGION = os.getenv("AWS_REGION") or os.getenv("AWS_DEFAULT_REGION")
end
local AWS
local LAMBDA_SERVICE_CACHE = setmetatable({}, { __mode = "k" })


local function get_now()
  ngx_update_time()
  return ngx_now() * 1000 -- time is kept in seconds with millisecond resolution.
end


local AWSLambdaHandler = {
  PRIORITY = 750,
  VERSION = meta.version
}


function AWSLambdaHandler:init_worker()
  -- Initialize a global level AWS object for reusing
  local config = { region = AWS_REGION }
  AWS = aws(config)
end


function AWSLambdaHandler:access(conf)
  local region = conf.aws_region or AWS_REGION
  if not region then
    return error("no region specified")
  end

  local host = conf.host or fmt("lambda.%s.amazonaws.com", region)

  local port = conf.port or 443
  local scheme = conf.disable_https and "http" or "https"
  local endpoint = fmt("%s://%s", scheme, host)
  local proxy_opts
  if conf.proxy_url then
    proxy_opts = { http_proxy = conf.proxy_url, https_proxy = conf.proxy_url }
  end

  local lambda_service = LAMBDA_SERVICE_CACHE[conf]
  if not lambda_service then
    -- Overriding global proxy_opts so STS can use proxy too
    -- if no proxy then reset to default
    if proxy_opts then
      AWS.config.proxy_opts = proxy_opts
    else
      AWS.config.proxy_opts = nil
    end

    -- Override credential config according to plugin config
    -- We override global AWS object credentials here and
    -- make sure it gets updated when config changed.
    if conf.aws_key then
      local creds = AWS:Credentials {
        accessKeyId = conf.aws_key,
        secretAccessKey = conf.aws_secret,
      }

      AWS.config.credentials = creds
    end

    -- Assume role based on configuration
    if conf.aws_assume_role_arn then
      local sts, err = AWS:STS()
      if not sts then
        return error(fmt("unable to create AWS STS (%s)", err))
      end

      local sts_creds = AWS:ChainableTemporaryCredentials {
        params = {
          RoleArn = conf.aws_assume_role_arn,
          RoleSessionName = conf.aws_role_session_name,
        },
        sts = sts,
      }

      AWS.config.credentials = sts_creds
    end

    -- Create a new Lambda service object
    lambda_service = AWS:Lambda({
      region = region,
      endpoint = endpoint,
      port = port,
      timeout = conf.timeout,
      keepalive_idle_timeout = conf.keepalive,
      ssl_verify = false, -- TODO: set this default to true in the next major version
    })
    LAMBDA_SERVICE_CACHE[conf] = lambda_service
  end

  local upstream_body_json = build_request_payload(conf)

  -- TRACING: set KONG_WAITING_TIME start
  local kong_wait_time_start = get_now()

  local res, err = lambda_service:invoke({
    FunctionName = conf.function_name,
    InvocationType = conf.invocation_type,
    LogType = conf.log_type,
    Payload = upstream_body_json,
    Qualifier = conf.qualifier,
  })

  if err then
    return error(err)
  end

  local content = res.body
  if res.status >= 400 then
    return error(content)
  end

  -- TRACING: set KONG_WAITING_TIME stop
  local ctx = ngx.ctx
  -- setting the latency here is a bit tricky, but because we are not
  -- actually proxying, it will not be overwritten
  ctx.KONG_WAITING_TIME = get_now() - kong_wait_time_start

  local headers = res.headers

  -- We're responding with the header returned from Lambda service
  -- Remove hop-by-hop headers to prevent it from being sent to client
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


return AWSLambdaHandler
