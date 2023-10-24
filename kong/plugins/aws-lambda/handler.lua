-- Copyright (C) Kong Inc.

local ngx_var = ngx.var
local ngx_now = ngx.now
local ngx_update_time = ngx.update_time
local md5_bin = ngx.md5_bin
local fmt = string.format
local buffer = require "string.buffer"
local lrucache = require "resty.lrucache"

local kong = kong
local meta = require "kong.meta"
local constants = require "kong.constants"
local aws_config = require "resty.aws.config" -- reads environment variables, thus specified here
local VIA_HEADER = constants.HEADERS.VIA
local VIA_HEADER_VALUE = meta._NAME .. "/" .. meta._VERSION

local request_util = require "kong.plugins.aws-lambda.request-util"
local build_request_payload = request_util.build_request_payload
local extract_proxy_response = request_util.extract_proxy_response

local aws = require("resty.aws")
local AWS_GLOBAL_CONFIG
local AWS_REGION do
  AWS_REGION = os.getenv("AWS_REGION") or os.getenv("AWS_DEFAULT_REGION")
end
local AWS
local LAMBDA_SERVICE_CACHE


local function get_now()
  ngx_update_time()
  return ngx_now() * 1000 -- time is kept in seconds with millisecond resolution.
end


local function initialize()
  LAMBDA_SERVICE_CACHE = lrucache.new(1000)
  AWS_GLOBAL_CONFIG = aws_config.global
  AWS = aws()
  initialize = nil
end

local build_cache_key do
  -- Use AWS Service related config fields to build cache key
  -- so that service object can be reused between plugins and
  -- vault refresh can take effect when key/secret is rotated
  local SERVICE_RELATED_FIELD = { "timeout", "keepalive", "aws_key", "aws_secret",
                                  "aws_assume_role_arn", "aws_role_session_name",
                                  "aws_region", "host", "port", "disable_https",
                                  "proxy_url", "aws_imds_protocol_version" }

  build_cache_key = function (conf)
    local cache_key_buffer = buffer.new(100):reset()
    for _, field in ipairs(SERVICE_RELATED_FIELD) do
      local v = conf[field]
      if v then
        cache_key_buffer:putf("%s=%s;", field, v)
      end
    end

    return md5_bin(cache_key_buffer:get())
  end
end


local AWSLambdaHandler = {
  PRIORITY = 750,
  VERSION = meta.version
}


function AWSLambdaHandler:access(conf)
  if initialize then
    initialize()
  end

  -- The region in plugin configuraion has higher priority
  -- than the one in environment variable
  local region = conf.aws_region or AWS_REGION
  if not region then
    return error("no region specified")
  end

  local host = conf.host or fmt("lambda.%s.amazonaws.com", region)

  local port = conf.port or 443
  local scheme = conf.disable_https and "http" or "https"
  local endpoint = fmt("%s://%s", scheme, host)

  local cache_key = build_cache_key(conf)
  local lambda_service = LAMBDA_SERVICE_CACHE:get(cache_key)
  if not lambda_service then
    local credentials = AWS.config.credentials
    -- Override credential config according to plugin config
    -- Note that we will not override the credential in AWS
    -- singleton directly because it may be needed for other
    -- scenario
    if conf.aws_key then
      local creds = AWS:Credentials {
        accessKeyId = conf.aws_key,
        secretAccessKey = conf.aws_secret,
      }

      credentials = creds

    elseif conf.proxy_url
      -- If plugin config has proxy, then EKS IRSA might
      -- need it as well, so we need to re-init the AWS
      -- IRSA credential provider
      and AWS_GLOBAL_CONFIG.AWS_WEB_IDENTITY_TOKEN_FILE
      and AWS_GLOBAL_CONFIG.AWS_ROLE_ARN then
        local creds = AWS:TokenFileWebIdentityCredentials()
        creds.sts = AWS:STS({
          region = region,
          stsRegionalEndpoints = AWS_GLOBAL_CONFIG.sts_regional_endpoints,
          ssl_verify = false,
          http_proxy = conf.proxy_url,
          https_proxy = conf.proxy_url,
        })

        credentials = creds
    end

    -- Assume role based on configuration
    if conf.aws_assume_role_arn then
      local sts, err = AWS:STS({
        credentials = credentials,
        region = region,
        stsRegionalEndpoints = AWS_GLOBAL_CONFIG.sts_regional_endpoints,
        ssl_verify = false,
        http_proxy = conf.proxy_url,
        https_proxy = conf.proxy_url,
      })
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

      credentials = sts_creds
    end

    -- Create a new Lambda service object
    lambda_service = AWS:Lambda({
      credentials = credentials,
      region = region,
      endpoint = endpoint,
      port = port,
      timeout = conf.timeout,
      keepalive_idle_timeout = conf.keepalive,
      ssl_verify = false, -- TODO: set this default to true in the next major version
      http_proxy = conf.proxy_url,
      https_proxy = conf.proxy_url,
    })
    LAMBDA_SERVICE_CACHE:set(cache_key, lambda_service)
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
    return error(content.Message)
  end

  -- TRACING: set KONG_WAITING_TIME stop
  local ctx = ngx.ctx
  -- setting the latency here is a bit tricky, but because we are not
  -- actually proxying, it will not be overwritten
  ctx.KONG_WAITING_TIME = get_now() - kong_wait_time_start

  local headers = res.headers

  -- Remove Content-Length header returned by Lambda service,
  -- to make sure returned response length will be correctly calculated
  -- afterwards.
  headers["Content-Length"] = nil
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
