-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

--
-- private vars
--

local supported_vector_databases = {
  redis = "kong.ai.semantic_cache.drivers.redis",
}

--
-- public functions
--

-- Initializes the appropriate vector database driver given its name.
--
-- @param vectordb_config the configuration for the vector database driver
-- @return the driver module
-- @return nothing. throws an error if any
local function new(vectordb_config)
  local driver_name = vectordb_config and vectordb_config.driver
  if not driver_name then
    return nil, "empty name provided for vector database driver"
  end

  local driver_modname = supported_vector_databases[driver_name]
  if not driver_modname then
    return nil, string.format("unsupported vector database driver: %s", driver_name)
  end

  local driver_mod = require(driver_modname)
  return driver_mod:new(vectordb_config)
end

--
-- module
--

return {
  -- functions
  new = new
}
