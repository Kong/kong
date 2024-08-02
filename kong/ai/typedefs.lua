-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

--
-- typedefs
--
local typedefs = require("kong.db.schema.typedefs")

-- the authentication configuration for the vector database.
local auth = {
  type     = "record",
  required = false,
  fields   = {
    {
      password = {
        type          = "string",
        description   = "authentication password",
        required      = false,
        referenceable = true,
        encrypted     = true,  -- [[ ee declaration - it masks the sensitive field in the UI ]]
      },
    },
    {
      token = {
        type          = "string",
        description   = "authentication token",
        required      = false,
        referenceable = true,
        encrypted     = true,  -- [[ ee declaration - it masks the sensitive field in the UI ]]
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
      provider = {
        type        = "string",
        description = "which provider to use for embeddings",
        required    = true,
        one_of      = {
          "mistralai",
          "openai",
        },
      },
    },
    {
      name = {
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
      upstream_url = typedefs.url({
        type        = "string",
        description = "upstream url for the embeddings",
        required    = false,
      }),
    },
  },
}


--
-- module
--

return {
  -- typedefs
  embeddings = embeddings,
}
