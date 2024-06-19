-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require("kong.db.schema.typedefs")
local Schema = require "kong.db.schema"
local llm = require("kong.llm")

local deep_copy = require("kong.tools.table").deep_copy

local target_schema = deep_copy(llm.config_schema)

local nonzero_timeout = Schema.define {
  type = "integer",
  between = { 1, math.pow(2, 31) - 2 },
}

table.insert(target_schema.fields, #target_schema.fields, {
  weight = { description = "The weight this target gets within the upstream loadbalancer (1-65535).", type = "integer", default = 100, between = { 1, 65535 }, },
})

return {
  name = "ai-proxy-advanced",
  fields = {
    { protocols = typedefs.protocols_http },
    { config = {
      type = "record",
      fields = {
        { balancer = {
          type = "record",
          required = true,
          fields = {
            { algorithm = { description = "Which load balancing algorithm to use.", type = "string",
              default = "round-robin",
              one_of = { "round-robin", "lowest-latency", "lowest-usage", "consistent-hashing" },
            }, },
            { tokens_count_strategy = { description = "What tokens to use for usage calculation. Available values are: `total_tokens` `prompt_tokens`, and `completion_tokens`.", type = "string",
              default = "total_tokens",
              one_of = { "total_tokens", "prompt_tokens", "completion_tokens" },
            }},
            { hash_on_header = { description = "The header to use for consistent-hashing.", type = "string",
              default = "X-Kong-LLM-Request-ID",
            }},
            { slots = { description = "The number of slots in the load balancer algorithm.", type = "integer", default = 10000, between = { 10, 2^16 }, }, },
            { retries = { description = "The number of retries to execute upon failure to proxy.",
              type = "integer", default = 5, between = { 0, 32767 } }, },
            { connect_timeout = nonzero_timeout { default = 60000 }, },
            { write_timeout = nonzero_timeout { default = 60000 }, },
            { read_timeout = nonzero_timeout { default = 60000 }, },
        }, }, },
        { targets = {
          type = "array",
          required = true,
          elements = target_schema,
        }, },
      }, -- fields
    }, }, -- config
  },
}
