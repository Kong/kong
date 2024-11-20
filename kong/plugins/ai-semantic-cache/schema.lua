-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local PLUGIN_NAME = "ai-semantic-cache"

local typedefs    = require("kong.db.schema.typedefs")
local llm         = require("kong.llm")

local schema = {
  name = PLUGIN_NAME,
  fields = {
    -- the 'fields' array is the top-level entry with fields defined by Kong
    { protocols = typedefs.protocols_http },
    {
      config = {
        type = "record",
        fields = {
          { message_countback = {
              description = "Number of messages in the chat history to Vectorize/Cache",
              type = "number",
              between = { 1, 1000 },
              default = 1 }},
          { ignore_system_prompts = {
              description = "Ignore and discard any system prompts when Vectorizing the request",
              type = "boolean",
              default = false }},
          { ignore_assistant_prompts = {
              description = "Ignore and discard any assistant prompts when Vectorizing the request",
              type = "boolean",
              default = false }},
          {
            ignore_tool_prompts = {
              description = "Ignore and discard any tool prompts when Vectorizing the request",
              type = "boolean",
              default = false }},
          { stop_on_failure = {
              description = "Halt the LLM request process in case of a caching system failure",
              type = "boolean",
              required = true,
              default = false }},
          { cache_ttl = { description = "TTL in seconds of cache entities. Must be a value greater than 0.",
              type = "integer",
              default = 300,
              gt = 0 }},
          { cache_control = { description = "When enabled, respect the Cache-Control behaviors defined in RFC7234.",
              type = "boolean",
              default = false,
              required = true }},
          { exact_caching = { description = "When enabled, a first check for exact query will be done. It will impact DB size",
              type = "boolean",
              required = true,
              default = false }},
          { embeddings = llm.embeddings_schema },
          { vectordb = llm.vectordb_schema },
        },
      },
    },
  },
}

return schema
