-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson        = require "cjson.safe"
local ngx          = ngx
local type         = type
local setmetatable = setmetatable
local _M           = {}

--- Create new memory strategy object
-- @table opts Strategy options: contains 'dictionary_name' field
function _M.new(opts)
  local dict = ngx.shared[opts.dictionary_name]

  local self = {
    dict = dict,
    opts = opts,
  }

  return setmetatable(self, {
    __index = _M,
  })
end

--- Fetch data from the cache
-- @param key (string) the unique identifier to use to retrieve the cached data
-- @return (any) the cached data
function _M:fetch(key)
  if type(key) ~= "string" then
    return nil, "key must be a string"
  end

  local data, err = self.dict:get(key)
  if (not data) or type(data) ~= "string" then
    return nil, err
  end

  return cjson.decode(data)
end

--- Cache data in the shared memory
-- @param key (string) the unique identifier under which the data will be cached
-- @param data (any) the data to be cached
-- @param ttl (number) the time to live for the data in the cache in seconds. Must be a positive number. Supports up to ms accuracy (0.001)
function _M:store(key, data, ttl)
  if type(key) ~= "string" then
    return nil, "key must be a string"
  elseif type(ttl) ~= "number" or ttl <= 0 then
    return nil, "ttl must be a number greater than or equal to 0"
  end

  local json = cjson.encode(data)
  if not json then
    return nil, "could not encode request object"
  end
  return self.dict:set(key, json, ttl)
end

--- Purge data from the cache
-- @param key (string) the unique identifier to use to purge the cached data
function _M:purge(key)
  if type(key) ~= "string" then
    return nil, "key must be a string"
  end
  self.dict:delete(key)
  return true
end

return _M
