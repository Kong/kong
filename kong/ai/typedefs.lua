-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

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
      },
    },
    {
      token = {
        type        = "string",
        description = "authentication token",
        required    = false,
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
  },
}

-- the TLS configuration for the vector database
local tls = {
  type     = "record",
  required = false,
  fields   = {
    {
      ssl = {
        type        = "boolean",
        description = "require TLS communication",
        required    = false,
        default     = true,
      },
    },
    {
      ssl_verify = {
        type        = "boolean",
        description = "verify SSL certificates during TLS",
        required    = false,
        default     = true,
      },
    },
  }
}

-- the Vector Database configuration
local vectordb = {
  type     = "record",
  required = true,
  fields   = {
    { auth = auth },
    { tls = tls },
    {
      driver = {
        type        = "string",
        description = "which vector database driver to use",
        required    = true,
        one_of      = { "redis" },
      },
    },
    {
      url = {
        type        = "string",
        description = "the URL endpoint to reach the vector database",
        required    = true,
      },
    },
    {
      index = {
        type        = "string",
        description = "the name of the index by which vectors can be searched (relevant for redis)",
        required    = false,
        default     = "kong_aigateway",
      },
    },
    {
      dimensions = {
        type        = "integer",
        description = "the desired dimensionality for the vectors",
        required    = true,
      },
    },
    {
      default_threshold = {
        type        = "number",
        description = "the default similarity threshold for accepting semantic search results (float)",
        required    = true,
      },
    },
    {
      distance_metric = {
        type        = "string",
        description = "the distance metric to use for vector searches",
        required    = true,
        one_of      = { "COSINE", "EUCLIDEAN" },
      },
    },
  },
}

--
-- module
--

return {
  -- typedefs
  embeddings = embeddings,
  vectordb   = vectordb,
}
