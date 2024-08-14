-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson                     = require "cjson.safe"
local redis                     = require "kong.enterprise_edition.tools.redis.v2"
local utils                     = require "kong.tools.utils"
local DEFAULT_KEEPALIVE_TIMEOUT = 55 * 1000
local DEFAULT_KEEPALIVE_CONS    = 1000
local type                      = type
local _M                        = {}

function _M.new(opts)
  local conf = utils.deep_copy(opts)

  return setmetatable(
    { conf = conf },
    { __index = _M }
  )
end

--- Fetch data from the backing Redis database
-- @param key (string) the unique identifier under which the data will be cached
function _M:fetch(key)
  if type(key) ~= "string" then
    return nil, "key must be a string"
  end

  local red, err = redis.connection(self.conf)
  if not red then
    return nil, "unable to connect to redis: " .. err
  end
  local data, err = red:get(key)
  if (not data) or type(data) ~= "string" then
    return nil, err
  end

  red:set_keepalive(DEFAULT_KEEPALIVE_TIMEOUT, DEFAULT_KEEPALIVE_CONS)
  return cjson.decode(data)
end

--- Cache data in the Redis database
-- @param key (string) the unique identifier under which the data will be cached
-- @param data (any) the data to be cached
-- @param ttl (number) the time to live for the data in the cache in seconds. Must be a positive number. Supports up to ms accuracy (0.001)
function _M:store(key, data, ttl)
  if type(key) ~= "string" then
    return nil, "key must be a string"
  elseif type(ttl) ~= "number" or ttl <= 0 then
    return nil, "ttl must be a number greater than or equal to 0"
  end

  local red, err = redis.connection(self.conf)
  if not red then
    return nil, "unable to connect to redis: " .. err
  end

  local json = cjson.encode(data)
  if not json then
    return nil, "could not encode request object"
  end

  local result, err = red:set(key, json, "EX", ttl)
  local success = result == "OK"
  if not success then
    return nil, "failed to store data in cache: " .. err
  end

  red:set_keepalive(DEFAULT_KEEPALIVE_TIMEOUT, DEFAULT_KEEPALIVE_CONS)
  return success
end

--- Purge data from the cache
-- @param key (string) the unique identifier to use to purge the cached data
function _M:purge(key)
  if type(key) ~= "string" then
    return nil, "key must be a string"
  end

  local red, err = redis.connection(self.conf)
  if not red then
    return nil, "unable to connect to redis: " .. err
  end

  local _, err = red:del(key)
  if err then
    return nil, "failed to delete from cache: " .. err
  end
  red:set_keepalive(DEFAULT_KEEPALIVE_TIMEOUT, DEFAULT_KEEPALIVE_CONS)
  return true
end

return _M
