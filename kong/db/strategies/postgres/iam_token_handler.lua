-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local lrucache = require "resty.lrucache"
local re_match = ngx.re.match
local fmt = string.format
local min = math.min
local max = math.max

local aws
local rds
local RDS_IAM_AUTH_EXPIRE_TIME = 15 * 60

local TOKEN_CACHE = lrucache.new(20)

-- Concatenating the rds keyword with common endpoint suffixes
-- This works for both RDS default endpoints and custom endpoints since
-- they all end with the same suffix, for example `rds.amazonaws.com`
-- Ref: https://github.com/aws/aws-sdk-js/blob/bdc8b02d572056d6647c9a6d320428c3d5161981/lib/region_config.js#L87-L92
local regionRegexes = {
  [[(?<region>(us|eu|ap|sa|ca|me)\-\w+\-\d+)\.rds\.amazonaws\.com]],
  [[(?<region>cn\-\w+\-\d+)\.rds\.amazonaws\.com\.cn]],
  [[(?<region>us\-gov\-\w+\-\d+)\.rds\.amazonaws\.com]],
  [[(?<region>us\-iso\-\w+\-\d+)\.rds\.c2s\.ic\.gov]],
  [[(?<region>us\-isob\-\w+\-\d+)\.rds\.sc2s\.sgov\.gov]]
}


local function init()
  local AWS = require("resty.aws")
  -- Note: cannot move to the module level because it contains network io
  -- which will yield, and yield cannot happens inside require
  local AWS_global_config = require("resty.aws.config").global
  local config = { region = AWS_global_config.region }

  aws = AWS(config)
  if not aws then
    return nil, "failed to instantiate aws"
  end

  local err
  rds, err = aws:RDS()
  if not rds then
    return nil, fmt("failed to instantiate rds (%s)", err)
  end
end


local function extract_region_from_db_endpoint(endpoint)
  for _, regex in ipairs(regionRegexes) do
    local m = re_match(endpoint, regex, 'jo')
    if m then
      return m.region
    end
  end
end


local function generate_conf_key(conf)
  return "IAM_TOKEN" .. ":" .. conf.host .. ":" .. conf.port .. ":" .. conf.user .. ":" .. conf.database
end


local function raw_get(conf)
  local db_region = extract_region_from_db_endpoint(conf.host)
  if not db_region then
    return nil, "cannot fetch IAM token because extract region from db endpoint failed"
  end

  local signer = rds:Signer {
    hostname = conf.host,
    port = conf.port,
    username = conf.user,
    region = db_region,
  }

  local res, err = signer:getAuthToken()
  if not res then
    return nil, fmt("failed to fetch IAM token from token handler (%s)", err)
  end

  -- getAuthToken should have already refreshed the credential, so we fetch the expire time directly
  local status, _, _, _, cred_expire_timestamp = rds.config.credentials:get()
  if not status then
    cred_expire_timestamp = ngx.now() + RDS_IAM_AUTH_EXPIRE_TIME
  end

  local cred_expire_time = max(0, cred_expire_timestamp - ngx.now())
  -- Leave a 15sec expiry window to make sure we refresh the token on time
  local rds_iam_token_expire_time = max(0, min(RDS_IAM_AUTH_EXPIRE_TIME, cred_expire_time) - 15)
  TOKEN_CACHE:set(generate_conf_key(conf), res, rds_iam_token_expire_time)

  return res
end


local function get(conf)
  local res = TOKEN_CACHE:get(generate_conf_key(conf))
  if res then
    return res
  end

  return raw_get(conf)
end


return {
  init = init,
  get = get
}
