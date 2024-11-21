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
local auth_schema = require("kong.llm.schemas.auth")

-- the configuration for embeddings, which are the vector representations of
-- inference prompts.
return {
  type     = "record",
  required = true,
  fields   = {
    { auth = auth_schema },
    { model = {
      type     = "record",
      required = true,
      fields   = {
        {
          provider = {
            type        = "string",
            description = "AI provider format to use for embeddings API",
            required    = true,
            one_of      = {
              "openai",
              "mistral",
            },
          },
        },
        {
          name = {
            type        = "string",
            description = "Model name to execute.",
            required    = true,
          },
        },
        {
          options = {
            description = "Key/value settings for the model",
            type = "record",
            required = false,
            fields = {
              {
                upstream_url = typedefs.url({
                  type        = "string",
                  description = "upstream url for the embeddings",
                  required    = false,
                }),
              },
            }
          },
        },
      }
    }, },
  },
}
