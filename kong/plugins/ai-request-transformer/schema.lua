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
            required = true,
        }},
        { transformation_extract_pattern = {
            description = "Defines the regular expression that must match to indicate a successful AI transformation "
                       .. "at the request phase. The first match will be set as the outgoing body. "
                       .. "If the AI service's response doesn't match this pattern, it is marked as a failure.",
            type = "string",
            required = false,
        }},
        { http_timeout = {
            description =  "Timeout in milliseconds for the AI upstream service.",
            type = "integer",
            required = true,
            default = 60000,
        }},
        { https_verify = {
          description = "Verify the TLS certificate of the AI upstream service.",
          type = "boolean",
          required = true,
          default = true,
        }},

        -- from forward-proxy
        { http_proxy_host = typedefs.host },
        { http_proxy_port = typedefs.port },
        { https_proxy_host = typedefs.host },
        { https_proxy_port = typedefs.port },

        { llm = llm.config_schema },
      },
    }},
    
  },
  entity_checks = {
    {
      conditional = {
        if_field = "config.llm.route_type",
        if_match = {
          not_one_of = {
            "llm/v1/chat",
          }
        },
        then_field = "config.llm.route_type",
        then_match = { eq = "llm/v1/chat" },
        then_err = "'config.llm.route_type' must be 'llm/v1/chat' for AI transformer plugins",
      },
    },
    { mutually_required = { "config.http_proxy_host", "config.http_proxy_port" } },
    { mutually_required = { "config.https_proxy_host", "config.https_proxy_port" } },
  },
}
