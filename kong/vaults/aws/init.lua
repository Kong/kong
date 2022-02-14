-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local cjson = require("cjson.safe").new()


local aws = require("resty.aws")
local EnvironmentCredentials = require "resty.aws.credentials.EnvironmentCredentials"


local fmt = string.format
local type = type
local encode_json = cjson.encode
local getenv = os.getenv

local AWS
local AWS_REGION


local function init()
  -- might call API and can cause 5 secs latency on startup if not on AWS
  -- aws_utils.getCurrentRegion()
  AWS_REGION = getenv("AWS_REGION") or getenv("AWS_DEFAULT_REGION")

  -- AWS_SECRET_ACCESS_KEY and AWS_ACCESS_KEY_ID will be read
  -- TODO: validate if they are set. Also allow to have different Credentials. Out of scope for alpha
  AWS = aws({ credentials = EnvironmentCredentials.new() })
end


local function get(conf, resource, version)
  local region = conf.region or AWS_REGION
  if not region then
    return nil, "aws secret manager requires region"
  end

  local sm, err = AWS:SecretsManager({ region = region })
  if not sm then
    return nil, fmt("unable to create aws secret manager (%s)", err)
  end

  if not version or version == 1 then
    version = "AWSCURRENT"
  elseif version == 2 then
    version = "AWSPREVIOUS"
  else
    return nil, "invalid version for aws secret manager"
  end

  local res
  res, err = sm:getSecretValue({
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
  VERSION = "1.0.0",
  init = init,
  get = get,
}
