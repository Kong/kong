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
  openai = "kong.llm.embeddings.drivers.openai",
  mistral = "kong.llm.embeddings.drivers.mistral",
}

--
-- public functions
--

-- Initializes the appropriate embedding provider given its name.
--
-- @param embeddings_config the configuration for embeddings
-- @param dimensions the number of dimensions for generating embeddings
-- @return the provider module
-- @return nothing. throws an error if any
local function new(embeddings_config, dimensions)
  local provider_name = embeddings_config.model and embeddings_config.model.provider
  if not provider_name then
    return nil, "empty name provided for embeddings provider"
  end

  local provider_modname = supported_embeddings[provider_name]
  if not provider_modname then
    return nil, string.format("unsupported embeddings provider: %s", provider_name)
  end

  local provider_mod = require(provider_modname)
  return provider_mod:new(embeddings_config, dimensions), nil
end

--
-- module
--

return {
  -- functions
  new = new
}
