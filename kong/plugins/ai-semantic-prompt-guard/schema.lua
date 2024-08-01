-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"
local ai_typedefs = require("kong.ai.typedefs")
local vectordb = require("kong.llm.schemas.vectordb")

return {
  name = "ai-semantic-prompt-guard",
  fields = {
    { protocols = typedefs.protocols_http },
    { config = {
      type = "record",
      fields = {
          { embeddings = ai_typedefs.embeddings },
          { vectordb = vectordb },
          { search = {
            type     = "record",
            required = false,
            fields   = {
              {
                threshold = {
                  type = "number",
                  default = 0.5,
                  description = "Threshold for the similarity score to be considered a match.",
                  required = false,
                },
              }
            }
          }},
          { rules = {
            type     = "record",
            required = true,
            fields   = {
              {
                match_all_conversation_history = {
                  type = "boolean",
                  default = false,
                  required = false,
                  description = "If false, will ignore all previous chat prompts from the conversation history.",
                }
              },
              {
                allow_prompts = {
                  type = "array",
                  description = "List of prompts to allow.",
                  required = false,
                  len_max = 10,
                  elements = {
                    type = "string",
                    len_min = 1,
                    len_max = 500,
                  },
                },
              },
              {
                deny_prompts = {
                  type = "array",
                  description = "List of prompts to deny.",
                  required = false,
                  len_max = 10,
                  elements = {
                    type = "string",
                    len_min = 1,
                    len_max = 500,
                  },
                },
              },
              {
                max_request_body_size = {
                  type = "integer",
                  default = 8 * 1024,
                  gt = 0,
                  description = "max allowed body size allowed to be introspected",
                }
              },
              {
                match_all_roles = {
                  description = "If true, will match all roles in addition to 'user' role in conversation history.",
                  type = "boolean",
                  required = true,
                  default = false,
                }
              },
            }
          }}
        }
      }
    }
  },
  entity_checks = {
    {
      at_least_one_of = { "config.rules.allow_prompts", "config.rules.deny_prompts" },
    }
  }
}
