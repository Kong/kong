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
        { transform_request = {
            description = "Set true to enable request transformation, using the configured LLM block.",
            type = "boolean",
            required = true,
            default = true,
        }},
        { request_prompt = {
            description = "Use this prompt to tune the LLM system/assistant message for the incoming "
                       .. "proxy request (from the client), and what you are expecting in return.",
            type = "string",
            required = false,
        }},
        { request_transform_success_pattern = {
            description = "Defines the regular expression that must match to indicate a successful AI transformation "
                       .. "at the request phase. The first match will be set as the outgoing body. "
                       .. "If the AI service's response doesn't match this pattern, it is marked as a failure.",
            type = "string",
            required = false,
        }},
        { transform_response = {
            description = "Set true to enable response transformation, using the configured LLM block.",
            type = "boolean",
            required = true,
            default = false,
        }},
        { response_prompt = {
            description = "Use this prompt to tune the LLM system/assistant message for the returning proxy "
                      .. "request (from the upstream service), and what you are expecting in return.",
            type = "string",
            required = false,
        }},
        { parse_response_json_instructions = {
            description = "Set true to read specific response format from the LLM, during the response phase, "
                       .. "and set the status code / body / headers that proxy back to the client. "
                       .. "See plugin docs 'Overview' page for usage instructions.",
            type = "boolean",
            required = true,
            default = false,
        }},
        { response_transform_success_pattern = {
            description = "Defines the regular expression that must match to indicate a successful AI transformation "
                       .. "at the response phase. The first match will be set as the returning body. "
                       .. "If the AI service's response doesn't match this pattern, it is marked as a failure.",
            type = "string",
            required = false,
        }},
        { ssl_verify = {
            description = "Verify the TLS certificate of the Kong service URL and AI upstream services.",
            type = "boolean",
            required = true,
            default = true,
        }},
        { http_timeout = {
            description = "Timeout in milliseconds for the Kong service URL, and the AI upstream service.",
            type = "integer",
            required = true,
            default = 60000,
        }},
        { ssl_verify = {
            description = "Verify the TLS certificate of the Kong service URL, and the AI upstream service.",
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
