-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

--
-- private vars
--

local supported_embeddings = {
  openai = "kong.ai.embeddings.drivers.openai",
  mistralai = "kong.ai.embeddings.drivers.mistralai",
}

--
-- public functions
--

-- Initializes the appropriate embedding driver given its name.
--
-- @param embeddings_config the configuration for embeddings
-- @param dimensions the number of dimensions for generating embeddings
-- @return the driver module
-- @return nothing. throws an error if any
local function new(embeddings_config, dimensions)
  local driver_name = embeddings_config.driver
  if not driver_name then
    return nil, "empty name provided for embeddings driver"
  end

  local driver_modname = supported_embeddings[driver_name]
  if not driver_modname then
    return nil, string.format("unsupported embeddings driver: %s", driver_name)
  end

  local driver_mod = require(driver_modname)
  return driver_mod:new(embeddings_config, dimensions), nil
end

--
-- module
--

return {
  -- functions
  new = new
}
