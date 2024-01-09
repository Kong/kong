local typedefs = require("kong.db.schema.typedefs")
local llm = require("kong.llm")



return {
  name = "ai-response-transformer",
  fields = {
    { protocols = typedefs.protocols_http },
    { consumer = typedefs.no_consumer },
    { config = {
      type = "record",
      fields = {
        { prompt = {
            description = "Use this prompt to tune the LLM system/assistant message for the returning "
                       .. "proxy response (from the upstream), adn what response format you are expecting.",
            type = "string",
            required = false,
        }},
        { transformation_extract_pattern = {
            description = "Defines the regular expression that must match to indicate a successful AI transformation "
                       .. "at the response phase. The first match will be set as the returning body. "
                       .. "If the AI service's response doesn't match this pattern, a failure is returned to the client.",
            type = "string",
            required = false,
        }},
        { parse_llm_response_json_instructions = {
            description = "Set true to read specific response format from the LLM, "
                       .. "and accordingly set the status code / body / headers that proxy back to the client. "
                       .. "You need to engineer your LLM prompt to return the correct format, "
                       .. "see plugin docs 'Overview' page for usage instructions.",
            type = "boolean",
            required = true,
            default = false,
        }},
        { ssl_verify = {
            description = "Verify the TLS certificate of the AI upstream service.",
            type = "boolean",
            required = true,
            default = true,
        }},
        { http_timeout = {
            description = "Timeout in milliseconds for the AI upstream service.",
            type = "integer",
            required = true,
            default = 60000,
        }},
        { ssl_verify = {
            description = "Verify the TLS certificate of the AI upstream service.",
            type = "boolean",
            required = true,
            default = true,
        }},
        { llm = llm.config_schema },
      },
    }},
  },
  entity_checks = {},
}
