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
  entity_checks = {
    {
      custom_entity_check = {
        field_sources = { "config.targets", },
        fn = function(entity)
          -- anthorpic_version and azure_api_version doesn't appear in the body
          -- so mixing them will not be a problem
          local targets = entity.config.targets
          local must_format, must_provider, must_route_type

          for _, target in ipairs(targets) do
            local this_provider = target.model and target.model.provider
            if not must_provider then
              must_provider = this_provider
            end

            local this_route_type = target.model and target.model.route_type
            if not must_route_type then
              must_route_type = this_route_type
            end

            if must_route_type ~= this_route_type then
              return false, "mixing different route types are not supported"
            end

            local this_format
            if this_provider == "openai" then
              this_format = "openai"
            elseif this_provider == "llama2" then
              this_format = target.model and target.model.options and target.model.options.llama2_format
            elseif this_provider == "mistral" then
              this_format = target.model and target.model.options and target.model.options.mistral_format
            end
            if not must_format then
              must_format = this_format
            end

            if must_provider ~= this_provider then -- if provider mismatches, check if format is same
              if not this_format or must_format ~= this_format then
                return false, "mixing different providers are not supported"
              end
            elseif this_format and must_format ~= this_format then -- if provider matches, but format doesn't
              return false, "mixing different providers with different formats are not supported"
            end
          end

          return true
        end
      }
    },
  }
}
