local http  = require "resty.http"
local json  = require "cjson"
local aws_v4 = require "kong.plugins.aws-lambda.v4"
local utils = require "kong.tools.utils"
local pl_file = require "pl.file"
local ngx_now = ngx.now
local kong = kong

local DEFAULT_SESSION_DURATION_SECONDS = 3600
local DEFAULT_HTTP_CLINET_TIMEOUT = 60000
local DEFAULT_ROLE_SESSION_NAME = "kong"


local function get_regional_sts_endpoint(aws_region)
  if aws_region then
    return 'sts.' .. aws_region .. '.amazonaws.com'
  else
    return 'sts.amazonaws.com'
  end
end

local function fetch_credentials_with_web_identity(config)
  if not config.aws_web_identity_role_arn then
    return nil, "Missing required parameter 'config.aws_web_identity_role_arn' for" ..
    " fetching credentials with web identity"
  end

  local aws_role_session_name = config.aws_role_session_name or DEFAULT_ROLE_SESSION_NAME

  if not config.aws_web_identity_token_file then
    return nil, "Missing required parameter 'config.aws_web_identity_token_file' for" ..
    ' fetching credentials with web identity'
  end

  local web_identity_token, err = pl_file.read(config.aws_web_identity_token_file)
  if not web_identity_token then
    local err_s = 'Unable to assume role [' ..  config.aws_web_identity_role_arn .. '] with web' ..
    ' identity error reading web identity token file: ' .. tostring(err)
    return nil, err_s
  end

  kong.log.debug('Trying to assume role [', config.aws_web_identity_role_arn, '] with web identity token')

  local sts_host = get_regional_sts_endpoint(config.aws_region)

  local assume_role_request_headers = {
    Accept                    = "application/json",
    ["Content-Type"]          = "application/x-www-form-urlencoded; charset=utf-8",
    Host                      = sts_host
  }

  local assume_role_query_params = {
    Action          = "AssumeRoleWithWebIdentity",
    Version         = "2011-06-15",
    RoleArn         = config.aws_web_identity_role_arn,
    DurationSeconds = DEFAULT_SESSION_DURATION_SECONDS,
    RoleSessionName = aws_role_session_name,
    WebIdentityToken = web_identity_token,
  }

  local sts_url = 'https://' .. sts_host .. '?' .. utils.encode_args(assume_role_query_params)

  -- Call STS to assume role
  local client = http.new()
  client:set_timeout(DEFAULT_HTTP_CLINET_TIMEOUT)
  local res, err = client:request_uri(sts_url, {
    method = "GET",
    headers = assume_role_request_headers,
    ssl_verify = false,
  })

  if err then
    local err_s = 'Unable to assume role [' ..  config.aws_web_identity_role_arn .. '] with web identity' ..
                  ' due to: ' .. tostring(err)
    return nil, err_s
  end

  if res.status ~= 200 then
    local err_s = 'Unable to assume role [' .. config.aws_web_identity_role_arn .. '] with web identity due' ..
                  '  to: status [' .. res.status .. '] - ' ..
                  'reason [' .. res.body .. ']'
    return nil, err_s
  end

  local credentials = json.decode(res.body).AssumeRoleWithWebIdentityResponse.AssumeRoleWithWebIdentityResult.Credentials
  local result = {
    access_key    = credentials.AccessKeyId,
    secret_key    = credentials.SecretAccessKey,
    session_token = credentials.SessionToken,
    expiration    = credentials.Expiration
  }

  return result, nil, result.expiration - ngx_now()
end

local function fetch_assume_role_credentials(aws_region, assume_role_arn,
                                             role_session_name, access_key,
                                             secret_key, session_token)
  if not assume_role_arn then
    return nil, "Missing required parameter 'assume_role_arn' for fetching STS credentials"
  end

  role_session_name = role_session_name or DEFAULT_ROLE_SESSION_NAME

  kong.log.debug('Trying to assume role [', assume_role_arn, ']')

  local sts_host = get_regional_sts_endpoint(aws_region)

  -- build the url and signature to assume role
  local assume_role_request_headers = {
    Accept                    = "application/json",
    ["Content-Type"]          = "application/x-www-form-urlencoded; charset=utf-8",
    ["X-Amz-Security-Token"]  = session_token,
    Host                      = sts_host
  }

  local assume_role_query_params = {
    Action          = "AssumeRole",
    Version         = "2011-06-15",
    RoleArn         = assume_role_arn,
    DurationSeconds = DEFAULT_SESSION_DURATION_SECONDS,
    RoleSessionName = role_session_name,
  }

  local assume_role_sign_params = {
    region          = aws_region,
    service         = "sts",
    access_key      = access_key,
    secret_key      = secret_key,
    method          = "GET",
    host            = sts_host,
    port            = 443,
    headers         = assume_role_request_headers,
    query           = utils.encode_args(assume_role_query_params)
  }

  local request, err
  request, err = aws_v4(assume_role_sign_params)

  if err then
    return nil, 'Unable to build signature to assume role ['
      .. assume_role_arn .. '] - error :'.. tostring(err)
  end

  -- Call STS to assume role
  local client = http.new()
  client:set_timeout(DEFAULT_HTTP_CLINET_TIMEOUT)
  local res, err = client:request_uri(request.url, {
    method = request.method,
    headers = request.headers,
    ssl_verify = false,
  })

  if err then
    local err_s = 'Unable to assume role [' ..  assume_role_arn .. ']' ..
                  ' due to: ' .. tostring(err)
    return nil, err_s
  end

  if res.status ~= 200 then
    local err_s = 'Unable to assume role [' .. assume_role_arn .. '] due to:' ..
                  'status [' .. res.status .. '] - ' ..
                  'reason [' .. res.body .. ']'
    return nil, err_s
  end

  local credentials = json.decode(res.body).AssumeRoleResponse.AssumeRoleResult.Credentials
  local result = {
    access_key    = credentials.AccessKeyId,
    secret_key    = credentials.SecretAccessKey,
    session_token = credentials.SessionToken,
    expiration    = credentials.Expiration
  }

  return result, nil, result.expiration - ngx_now()
end


return {
  fetch_assume_role_credentials = fetch_assume_role_credentials,
  fetchCredentials = fetch_credentials_with_web_identity,
}
