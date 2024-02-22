-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local redis = require "resty.redis"
local version = require "version"

local DEFAULT_TIMEOUT = 2000


local function connect(host, port)
  local redis_client = redis:new()
  redis_client:set_timeout(DEFAULT_TIMEOUT)
  assert(redis_client:connect(host, port))

  local red_password = os.getenv("REDIS_PASSWORD") or nil -- This will allow for testing with a secured redis instance
  if red_password then
    assert(redis_client:auth(red_password))
  end

  local red_version = string.match(redis_client:info(), 'redis_version:([%g]+)\r\n')
  return redis_client, assert(version(red_version))
end

local function reset_redis(host, port)
  local redis_client = connect(host, port)
  redis_client:flushall()
  redis_client:close()
end

local function add_admin_user(redis_client, username, password)
  assert(redis_client:acl("setuser", username, "on", "allkeys", "allcommands", ">" .. password))
end

local function add_basic_user(redis_client, username, password)
  assert(redis_client:acl("setuser", username, "on", "allkeys", "+get", ">" .. password))
end

local function remove_user(redis_client, username)
  assert(redis_client:acl("deluser", username))
end


return {
  connect = connect,
  add_admin_user = add_admin_user,
  add_basic_user = add_basic_user,
  remove_user = remove_user,
  reset_redis = reset_redis,
}
