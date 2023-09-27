-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local meta = require "kong.meta"
local cjson = require("cjson.safe").new()


local aws = require("resty.aws")
local aws_config = require("resty.aws.config")
local http = require("resty.http")
local lrucache = require "resty.lrucache"

local fmt = string.format
local type = type
local encode_json = cjson.encode

local AWS
local AWS_GLOBAL_CONFIG
local SECRETS_MANAGER_SERVICE_LRU


local function get_service_cache_key(conf)
  -- conf table cannot be used directly because
  -- it is generated every time when resolving
  -- reference
  return fmt("%s:%s:%s:%s", conf.region,
             conf.endpoint_url,
             conf.assume_role_arn,
             conf.role_session_name)
end


local function init()
  SECRETS_MANAGER_SERVICE_LRU = lrucache.new(20)
end


local function initialize_aws()
  AWS_GLOBAL_CONFIG = aws_config.global
  -- Initializing with CredentialProviderChain(default) and let it
  -- auto-detect the credentials for IAM Role.
  AWS = aws()
  initialize_aws = nil
end


local function get(conf, resource, version)
  if initialize_aws then
    initialize_aws()
  end

  local region = conf.region or AWS_GLOBAL_CONFIG.region
  if not region then
    return nil, "aws secret manager requires region"
  end

  local scheme, host, port, _, _ = unpack(http:parse_uri(conf.endpoint_url or fmt("https://secretsmanager.%s.amazonaws.com", region)))
  local endpoint = scheme .. "://" .. host

  local service_cache_key = get_service_cache_key(conf)
  local sm_service = SECRETS_MANAGER_SERVICE_LRU:get(service_cache_key)
  if not sm_service then
    local credentials = AWS.config.credentials
    -- Assume role if specified
    if conf.assume_role_arn then
      local sts, err = AWS:STS({
        region = region,
        stsRegionalEndpoints = AWS_GLOBAL_CONFIG.sts_regional_endpoints,
      })
      if not sts then
        return nil, fmt("unable to create AWS STS (%s)", err)
      end

      local sts_creds = AWS:ChainableTemporaryCredentials {
        params = {
          RoleArn = conf.assume_role_arn,
          RoleSessionName = conf.role_session_name,
        },
        sts = sts,
      }

      credentials = sts_creds
    end

    local err
    sm_service, err = AWS:SecretsManager({
      credentials = credentials,
      region = region,
      endpoint = endpoint,
      port = port,
    })
    if not sm_service then
      return nil, fmt("unable to create aws secret manager (%s)", err)
    end

    SECRETS_MANAGER_SERVICE_LRU:set(service_cache_key, sm_service)
  end

  if not version or version == 1 then
    version = "AWSCURRENT"
  elseif version == 2 then
    version = "AWSPREVIOUS"
  else
    return nil, "invalid version for aws secret manager"
  end

  local res, err = sm_service:getSecretValue({
    SecretId = resource,
    VersionStage = version,
  })

  if type(res) ~= "table" then
    if err then
      return nil, fmt("unable to retrieve secret from aws secret manager (%s)", err)
    end

    return nil, "unable to retrieve secret from aws secret manager (invalid response)"
  end

  if res.status ~= 200 then
    local body = res.body
    if type(body) == "table" then
      err = encode_json(body)
    end

    if err then
      return nil, fmt("failed to retrieve secret from aws secret manager (%s)", err)
    end

    return nil, "failed to retrieve secret from aws secret manager (invalid status code received)"
  end

  local body = res.body
  if type(body) ~= "table" then
    return nil, "unable to retrieve secret from aws secret manager (invalid response)"
  end

  local secret = body.SecretString
  if type(secret) ~= "string" then
    return nil, "unable to retrieve secret from aws secret manager (invalid secret string)"
  end

  return secret
end


return {
  name = "aws",
  VERSION = meta.core_version,
  init = init,
  get = get,
  license_required = true,
}
