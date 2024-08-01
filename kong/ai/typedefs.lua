-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local null = ngx.null

--
-- typedefs
--

-- the authentication configuration for the vector database.
local auth = {
  type     = "record",
  required = false,
  fields   = {
    {
      password = {
        type        = "string",
        description = "authentication password",
        required    = false,
        encrypted = true,  -- [[ ee declaration ]]
        referenceable = true
      },
    },
    {
      token = {
        type        = "string",
        description = "authentication token",
        required    = false,
        encrypted = true,  -- [[ ee declaration ]]
        referenceable = true
      },
    },
  },
}

-- the configuration for embeddings, which are the vector representations of
-- inference prompts.
local embeddings = {
  type     = "record",
  required = true,
  fields   = {
    { auth = auth },
    {
      driver = {
        type        = "string",
        description = "which driver to use for embeddings",
        required    = true,
        one_of      = {
          "mistralai",
          "openai",
        },
      },
    },
    {
      model = {
        type        = "string",
        description = "which AI model to use for generating embeddings",
        required    = true,
        one_of      = {
          -- openai
          "text-embedding-3-large",
          "text-embedding-3-small",
          -- mistralai
          "mistral-embed",
        },
      },
    },
    {
      upstream_url = {
        type        = "string",
        description = "upstream url for the embeddings",
        required    = false,
      },
    }
  },
  entity_checks = {
    { conditional = {
      if_field = "driver", if_match = { one_of = {"openai"} },
      then_field = "upstream_url",  then_match = { eq = null },
    } },
  }
}


--
-- module
--

return {
  -- typedefs
  embeddings = embeddings,
}
