-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local ee_redis  = require "kong.enterprise_edition.redis"

local vectordb = {
  type     = "record",
  required = true,
  fields   = {
    {
      strategy = {
      type        = "string",
        description = "which vector database driver to use",
        required    = true,
        one_of      = { "redis" },
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
      threshold = {
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
        one_of      = { "cosine", "euclidean" },
      },
    },
    { redis = ee_redis.config_schema, },
  },
}

return vectordb