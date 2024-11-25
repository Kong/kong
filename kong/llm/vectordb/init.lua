-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local utils = require("kong.tools.utils")

local supported_vector_databases = {
  redis = require("kong.llm.vectordb.strategies.redis"),
}

local _M = {}

--
-- public functions
--

-- Initializes the appropriate vector database driver given its name.
--
-- @tparam string strategy the name of the vector database driver
-- @tparam string namespace the namespace to isolate different scopes
-- @tparam table connector_config the configuration for the vector database driver
-- @treturn table the driver module
-- @treturn string error message if any
function _M.new(strategy, namespace, connector_config)
  if type(strategy) ~= "string" then
    return nil, "except strategy to be a string"
  end

  namespace = namespace or "kong_aigateway"

  if type(namespace) ~= "string" then
    return nil, "except namespace to be a string"
  end

  local mod = supported_vector_databases[strategy]
  if not mod then
    return nil, string.format("unsupported vector database strategy: %s", strategy)
  end

  local connector, err = mod.new(namespace, connector_config)
  if not connector then
    return nil, "failed to initialize vector database strategy: " .. err
  end

  return setmetatable({
    connector = connector,
  }, { __index = _M })
end


-- Insert an entry for a given vector and payload.
-- Generates a unique key is the format of <index>:<key_suffix>.
-- If key_suffix is not set, then a random UUID is generated.
-- The composed key is used as the primary key value, thus it must be unique for different vectors.
--
-- @tparam string vector the vector to insert
-- @tparam string|number|table payload the payload to insert
-- @tparam string[opt] key_suffix the suffix used to compose key.
-- @tparam number[opt] ttl the TTL of the key.
-- @treturn string the composed key for the entry
-- @treturn string error message if any
function _M:insert(vector, payload, key_suffix, ttl)
  key_suffix = key_suffix or utils.uuid()
  return self.connector:insert(vector, payload, key_suffix, ttl)
end


-- Retrieves an entry for a given vector.
--
-- @tparam string vector the vector to search
-- @tparam number[opt] threshold the proximity threshold for results
-- @tparam number[opt] threshold the proximity threshold for results
-- @tparam table[opt] metadata_out if passed a table the table will be fill with metadata of the search result
-- @treturn string|number|table|nil the payload, if any
-- @treturn string error message if any
function _M:search(vector, threshold, metadata_out)
  return self.connector:search(vector, threshold, metadata_out)
end


-- Keys retrieves all of a pattern of keys in this space.
-- 
-- @param pattern the search/filter pattern for keys
-- @treturn table the array of keys found from the given pattern
-- @treturn string error message if any
function _M:keys(pattern)
  return self.connector:keys(pattern)
end


-- Drop an index
--
-- @param index the index name to be deleted
-- @treturn boolean indicating success
-- @treturn string error message if any
function _M:drop_index(drop_records)
  return self.connector:drop_index(drop_records)
end


-- Delete an entry by pk.
--
-- @tparam string the primary key of the entry to delete
-- @treturn boolean indicating success
-- @treturn string error message if any
function _M:delete(pk)
  return self.connector:delete(pk)
end


-- Get an entry by pk.
--
-- @tparam string the primary key of the entry to delete
-- @tparam table[opt] metadata_out if passed a table the table will be fill with metadata of the search result
-- @treturn string|number|table|nil the payload, if any
-- @treturn string error message if any
function _M:get(pk, metadata_out)
  return self.connector:get(pk, metadata_out)
end

-- Set an entry by pk.
--
-- @tparam string the primary key of the entry to delete
-- @tparam string|number|table payload the payload to insert
-- @tparam number[opt] ttl the TTL of the key.
-- @treturn boolean indicating success
-- @treturn string error message if any
function _M:set(pk, payload, ttl)
  return self.connector:set(pk, payload, ttl)
end


return _M
