local typedefs = require("kong.db.schema.typedefs")
local llm = require("kong.llm")



return {
  name = "ai-request-transformer",
  fields = {
    { protocols = typedefs.protocols_http },
    { consumer = typedefs.no_consumer },
    { config = {
      type = "record",
      fields = {
        { prompt = {
            description = "Use this prompt to tune the LLM system/assistant message for the incoming "
                       .. "proxy request (from the client), and what you are expecting in return.",
            type = "string",
            required = false,
        }},
        { transformation_extract_pattern = {
            description = "Defines the regular expression that must match to indicate a successful AI transformation "
                       .. "at the request phase. The first match will be set as the outgoing body. "
                       .. "If the AI service's response doesn't match this pattern, it is marked as a failure.",
            type = "string",
            required = false,
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
