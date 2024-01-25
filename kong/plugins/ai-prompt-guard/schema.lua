local typedefs = require "kong.db.schema.typedefs"

return {
  name = "ai-prompt-guard",
  fields = {
    { protocols = typedefs.protocols_http },
    { config = {
      type = "record",
      fields = {
          { allow_patterns = {
              description = "Array of valid patterns, or valid questions from the 'user' role in chat.",
              type = "array",
              default = {},
              len_max = 10,
              elements = {
                type = "string",
                len_min = 1,
                len_max = 50,
              }}},
          { deny_patterns = {
              description = "Array of invalid patterns, or invalid questions from the 'user' role in chat.",
              type = "array",
              default = {},
              len_max = 10,
              elements = {
                type = "string",
                len_min = 1,
                len_max = 50,
              }}},
          { allow_all_conversation_history = {
              description = "If true, will ignore all previous chat prompts from the conversation history.",
              type = "boolean",
              required = true,
              default = false } },
        }
      }
    }
  },
  entity_checks = {
    {
      at_least_one_of = { "config.allow_patterns", "config.deny_patterns" },
    }
  }
}
