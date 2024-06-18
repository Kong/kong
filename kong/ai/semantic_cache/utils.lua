-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

--
-- imports
--

local utils = require("kong.tools.utils")

--
-- public functions
--

-- Given a simple name generates the full and opinionated name that we use as
-- a standard for all indexes managed by this driver.
--
-- @param index the name of the index
-- @return the full index name
local function full_index_name(index)
  return "idx:" .. index .. "_vss"
end

-- Returns a cache key for a given index. This is our opinioned way to store
-- semantic caching keys in the cache and to make them unique.
--
-- e.g. "kong_aigateway_semantic_cache:609594e6-9dee-410a-a9ea-a87745da8160"
--
-- The UUID can be provided for formatting an existing known key.
--
-- @param index the name of the index
-- @param uuid (optional) a known UUID to format the key
-- @return the unique cache key
local function cache_key(index, uuid)
  if not uuid then
    return index .. ":" .. utils.uuid()
  end

  return index .. ":" .. uuid
end

--
-- module
--

return {
  -- functions
  full_index_name = full_index_name,
  cache_key = cache_key,
}
