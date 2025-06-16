local typedefs = require "kong.db.schema.typedefs"

return {
  name = "ai-prompt-guard",
  fields = {
    { protocols = typedefs.protocols_http },
    { config = {
      type = "record",
      fields = {
          { allow_patterns = {
              description = "Array of valid regex patterns, or valid questions from the 'user' role in chat.",
              type = "array",
              required = false,
              len_max = 10,
              elements = {
                type = "string",
                len_min = 1,
                len_max = 500,
              }}},
          { deny_patterns = {
              description = "Array of invalid regex patterns, or invalid questions from the 'user' role in chat.",
              type = "array",
              required = false,
              len_max = 10,
              elements = {
                type = "string",
                len_min = 1,
                len_max = 500,
              }}},
          { allow_all_conversation_history = {
              description = "If true, will ignore all previous chat prompts from the conversation history.",
              type = "boolean",
              required = true,
              default = false } },
          { max_request_body_size = {
              type = "integer",
              default = 8 * 1024,
              gt = 0,
              description = "max allowed body size allowed to be introspected" } },
          { match_all_roles = {
              description = "If true, will match all roles in addition to 'user' role in conversation history.",
              type = "boolean",
              required = true,
              default = false } },
          { llm_format = {
              type = "string",
              default = "openai",
              required = false,
              description = "LLM input and output format and schema to use",
              one_of = { "openai", "bedrock", "gemini" } }},
          }
      }
    }
  },
  entity_checks = {
    {
      at_least_one_of = { "config.allow_patterns", "config.deny_patterns" },
    },
    { conditional = {
      if_field = "config.match_all_roles", if_match = { eq = true },
      then_field = "config.allow_all_conversation_history", then_match = { eq = false },
    } },
  }
}
