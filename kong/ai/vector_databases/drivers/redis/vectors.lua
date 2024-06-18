-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

--
-- imports
--

local cjson = require("cjson.safe")
local ffi = require("ffi")

--
-- private functions
--

-- Converts a given vector into a byte string.
--
-- It is currently required by Redis that vectors sent in with FT.SEARCH need
-- to be in a byte string format. We have to use their commands interface
-- directly (since Lua client support for Redis is limited at the time of
-- writing). They do this in their Python client by storing the vector as a
-- numpy array with float32 precision and then converting it to a byte string,
-- e.g.:
--
--   vector = [0.1, 0.2, 0.3]
--   array = numpy.array(vector, dtype=numpy.float32)
--   bytes = array.tobytes()
--
-- This function produces equivalent output, and is a bit of a hack. Ideally in
-- the future a higher level vector search API will be available in Redis so
-- we don't have to do this.
--
-- @param vector the vector to encode to bytes
-- @return the byte string representation of the vector
local function convert_vector_to_bytes(vector)
  local float_array = ffi.new("float[?]", #vector, unpack(vector))
  return ffi.string(float_array, ffi.sizeof(float_array))
end

-- Sets a cache entry in Redis.
--
-- @param red the initialized Redis client
-- @param key the cache key to set
-- @param payload the cache payload to set, as a table
-- @return boolean indicating success
-- @return nothing. throws an error if any
local function json_set(red, key, payload)
  local json_payload, err = cjson.encode(payload)
  if err then
    return err
  end
  return red["JSON.SET"](red, key, "$", json_payload)
end

--
-- public functions
--

-- Inserts a cache payload into Redis with an associated vector.
--
-- @param red the initialized Redis client
-- @param key the cache key to use
-- @param vector the vector to associate with the cache
-- @param payload the cache payload to insert
-- @return boolean indicating success
-- @return nothing. throws an error if any
local function create(red, key, vector, payload)
  local decoded_payload, err = cjson.decode(payload)
  if err then
    return false, err
  end
  decoded_payload.vector = vector -- inserting the vector into the payload is required by redis

  local _, err = json_set(red, key, decoded_payload)
  if err then
    return false, err
  end

  return true, nil
end

-- Performs a vector search on the Redis cache.
--
-- @param red the initialized Redis client
-- @param index the name of the index to search
-- @param vector the vector to search
-- @param threshold the proximity threshold for results
-- @return the search results, if any
-- @return an error message, if any
local function search(red, index, vector, threshold)
  kong.log.debug("[redis] performing vector search with threshold ", threshold)
  local res, err = red["FT.SEARCH"](red, index,
    "@vector:[VECTOR_RANGE $range $query_vector]=>{$YIELD_DISTANCE_AS: vector_score}",
    "SORTBY", "vector_score", "DIALECT", "2", "LIMIT", "0", "4", "PARAMS", "4", "query_vector",
    convert_vector_to_bytes(vector),
    "range", threshold
  )
  if err then
    return nil, err
  end

  -- Redis will return nothing when there are no keys in the prefix
  if #res == 0 then
    return
  end

  -- Redis will return a 0 when keys were found in the index prefix, but none matched
  if res[1] == 0 then
    return
  end

  local nested_table = res[3]
  if not nested_table then
    return nil, "unexpected search response: no value found in result set"
  end

  local json_payload = nested_table[4]
  if not json_payload then
    return nil, "unexpected search response: no JSON payload found in result set"
  end

  local decoded_payload, err = cjson.decode(json_payload)
  if err then
    return nil, err
  end

  -- redis requires that the vector be stored in the cache, but we don't want to return that to the user.
  -- we might consider later whether we would store the cache payload nested and adjacent and use another
  -- mechanism in the search to retrieve it without the vector.
  decoded_payload.vector = nil

  kong.log.debug("[redis] result found with score ", nested_table[2])
  return decoded_payload, nil
end

--
-- module
--

return {
  -- functions
  create = create,
  search = search,
}
