-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

--
-- public functions
--

-- Creates a new opinionated index in Redis for vector search, unless it already exists.
--
-- This will specifically create an index on a field called $.vector which
-- will need to be present in any cache entry searched via this index.
--
-- @param red the initialized Redis client
-- @param index the name of the index to create
-- @param prefix the prefix to use for the index
-- @param dimensions the number of dimensions in the vector
-- @param metric the distance metric to use for vector search
-- @return boolean indicating success
-- @return nothing. throws an error if any
local function create(red, index, prefix, dimensions, metric)
  local res, err = red["FT.CREATE"](red,
    index, "ON", "JSON",
    "PREFIX", "1", prefix .. ":", "SCORE", "1.0",
    "SCHEMA", "$.vector", "AS", "vector",
    "VECTOR", "FLAT", "6", "TYPE", "FLOAT32",
    "DIM", dimensions,
    "DISTANCE_METRIC", metric
  )
  if err and err ~= "Index already exists" then
    return false, err
  end

  kong.log.debug("[redis] index " .. (res and "created" or "already exists"))
  return true, nil
end

-- Deletes an index in Redis for vector search.
--
-- @param red the initialized Redis client
-- @param index the name of the index to delete
-- @return boolean indicating success
-- @return nothing. throws an error if any
local function delete(red, index)
  kong.log.debug("[redis] deleting index")
  local _, err = red["FT.DROPINDEX"](red, index)
  if err then
    return false, err
  end

  return true, nil
end

--
-- module
--

return {
  -- functions
  create = create,
  delete = delete,
}
