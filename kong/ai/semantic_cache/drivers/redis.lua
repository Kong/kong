-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

--
-- imports
--

local deep_copy = require("kong.tools.table").deep_copy

local index = require("kong.ai.vector_databases.drivers.redis.index")
local redis = require("kong.ai.vector_databases.drivers.redis.client")
local vectors = require("kong.ai.vector_databases.drivers.redis.vectors")
local utils = require("kong.ai.semantic_cache.utils")

---
--- private functions
---

-- Performs setup of the Redis database, including things like creating
-- indexes needed for vector search.
--
-- @param driver_config the configuration for the driver
-- @return boolean indicating success
-- @return nothing. throws an error if any
local function database_setup(driver_config)
  kong.log.debug("[redis] creating index")
  local index_name = utils.full_index_name(driver_config.index)
  local prefix = driver_config.index
  local succeded, err = index.create(
    driver_config.red,
    index_name,
    prefix,
    driver_config.dimensions,
    driver_config.distance_metric
  )
  if err then
    return false, err
  end

  if not succeded then
    return false, "failed to create index"
  end

  return true, nil
end

---
--- driver object
---

-- Driver is an interface for a redis database.
local Driver = {}
Driver.__index = Driver

-- Constructs a new Driver
--
-- @param provided_driver_config the configuration for the driver
-- @return the Driver object
-- @return nothing. throws an error if any
function Driver:new(provided_driver_config)
  local driver_config = deep_copy(provided_driver_config)

  local red, err = redis.create(driver_config)
  if err then
    return false, err
  end
  driver_config.red = red

  local _, err = database_setup(driver_config)
  if err then
    return nil, err
  end

  return setmetatable(driver_config, Driver), nil
end

-- Retrieves a cache entry for a given vector.
--
-- @param vector the vector to search
-- @param threshold the proximity threshold for results
-- @return the cache payload, if any
-- @return nothing. throws an error if any
function Driver:get_cache(vector, threshold)
  if not threshold then
    threshold = self.default_threshold
  end

  local index_name = utils.full_index_name(self.index)

  return vectors.search(self.red, index_name, vector, threshold)
end

-- Insert a cache entry for a given vector and payload.
-- Generates a unique cache key is the format of <index>:<vector>.
--
-- @param vector the vector to search
-- @param payload the payload to be cached as a JSON string
-- @return string the key id if successful
-- @return nothing. throws an error if any
function Driver:set_cache(vector, payload)
  local key = utils.cache_key(self.index)
  local ok, err = vectors.create(self.red, key, vector, payload)
  if err then
    return nil, err
  end
  return key
end

-- Delete a cache entry for a given vector and payload.
--
-- @param key the key to be deleted
-- @return boolean indicating success
-- @return nothing. throws an error if any
function Driver:delete_cache(key)
  return self.red["JSON.DEL"](self.red, key)
end

--
-- module
--

return Driver
