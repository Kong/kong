local typedefs = require("kong.db.schema.typedefs")
local llm = require("kong.llm")
local deep_copy = require("kong.tools.table").deep_copy

local this_schema = deep_copy(llm.config_schema)

local ai_proxy_only_config = {
    {
      response_streaming = {
        type = "string",
        description = "Whether to 'optionally allow', 'deny', or 'always' (force) the streaming of answers via server sent events.",
        required = false,
        default = "allow",
        one_of = { "allow", "deny", "always" }
    }},
    {
      max_request_body_size = {
        type = "integer",
        default = 8 * 1024,
        gt = 0,
        description = "max allowed body size allowed to be introspected"
    }},
    { model_name_header = { description = "Display the model name selected in the X-Kong-LLM-Model response header",
        type = "boolean", default = true
    }},
    { llm_format = {
        type = "string",
        default = "openai",
        required = false,
        description = "LLM input and output format and schema to use",
        one_of = { "openai", "bedrock", "gemini" }
    }},
    -- addition to this table will also need
    -- 1) add selected.FIELD = conf.FIELD in ai-proxy-advanced/filters/balance.lua
    -- 2) add propogation of top level key in monkey patch of spec-ee/03-plugins/44-ai-proxy-advanced/02-proxy_spec.lua
  }

for i, v in pairs(ai_proxy_only_config) do
  this_schema.fields[#this_schema.fields+1] = v
end

return {
  name = "ai-proxy",
  fields = {
    { protocols = typedefs.protocols_http },
    { config = this_schema },
  },
  entity_checks = {
    { conditional = {
        if_field = "config.llm_format", if_match = { one_of = { "bedrock", "gemini" }},
        then_field = "config.route_type", then_match = { eq = "llm/v1/chat" },
        then_err = "native provider options in llm_format can only be used with the 'llm/v1/chat' route_type",
    }},
    { conditional = {
        if_field = "config.llm_format", if_match = { eq = "bedrock" },
        then_field = "config.model.provider", then_match = { eq = "bedrock" },
        then_err = "native llm_format 'bedrock' can only be used with the 'bedrock' model.provider",
    }},
    { conditional = {
        if_field = "config.llm_format", if_match = { eq = "gemini" },
        then_field = "config.model.provider", then_match = { eq = "gemini" },
        then_err = "native llm_format 'gemini' can only be used with the 'gemini' model.provider",
    }},
  },
}
