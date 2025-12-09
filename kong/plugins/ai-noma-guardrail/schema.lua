-- +-------------------------------------------------------------+
--
--           Noma Security Guardrail Plugin for Kong
--                       https://noma.security
--
-- +-------------------------------------------------------------+

local typedefs = require("kong.db.schema.typedefs")

return {
  name = "ai-noma-guardrail",
  fields = {
    { protocols = typedefs.protocols_http },
    { config = {
      type = "record",
      fields = {
        -- OAuth2 authentication (preferred)
        { client_id = {
            description = "OAuth2 client ID for Noma API authentication.",
            type = "string",
            required = false,
            referenceable = true,
        }},
        { client_secret = {
            description = "OAuth2 client secret for Noma API authentication.",
            type = "string",
            required = false,
            encrypted = true,
            referenceable = true,
        }},
        { token_url = {
            description = "OAuth2 token endpoint URL. Defaults to {api_base}/v1/oauth/token.",
            type = "string",
            required = false,
        }},
        { api_base = {
            description = "Noma API base URL.",
            type = "string",
            required = true,
            default = "https://api.noma.security",
        }},
        { application_id = {
            description = "Application ID for Noma tracking. Defaults to 'kong' if not specified.",
            type = "string",
            required = false,
        }},
        { monitor_mode = {
            description = "If true, log violations but do not block requests. If false, block requests that violate policies.",
            type = "boolean",
            required = true,
            default = false,
        }},
        { block_failures = {
            description = "If true, block requests when Noma API fails to respond. If false, allow requests through on API failures.",
            type = "boolean",
            required = true,
            default = true,
        }},
        { anonymize_input = {
            description = "If true, replace sensitive data with anonymized version instead of blocking.",
            type = "boolean",
            required = true,
            default = false,
        }},
        { check_prompt = {
            description = "If true, check user prompts before sending to LLM.",
            type = "boolean",
            required = true,
            default = true,
        }},
        { check_response = {
            description = "If true, check LLM responses before returning to user.",
            type = "boolean",
            required = true,
            default = true,
        }},
        { http_timeout = {
            description = "Timeout in milliseconds for Noma API requests.",
            type = "integer",
            required = true,
            default = 60000,
        }},
        { https_verify = {
            description = "Verify the TLS certificate of the Noma API.",
            type = "boolean",
            required = true,
            default = true,
        }},
        { max_request_body_size = {
            description = "Maximum allowed body size to be introspected (in bytes).",
            type = "integer",
            default = 8 * 1024,
            gt = 0,
        }},
        { llm_format = {
            description = "LLM input and output format and schema to use.",
            type = "string",
            default = "openai",
            required = false,
            one_of = { "openai", "bedrock", "gemini" },
        }},
        -- Proxy configuration
        { http_proxy_host = typedefs.host },
        { http_proxy_port = typedefs.port },
        { https_proxy_host = typedefs.host },
        { https_proxy_port = typedefs.port },
      },
    }},
  },
  entity_checks = {
    { at_least_one_of = { "config.check_prompt", "config.check_response" } },
    { mutually_required = { "config.client_id", "config.client_secret" } },
    { mutually_required = { "config.http_proxy_host", "config.http_proxy_port" } },
    { mutually_required = { "config.https_proxy_host", "config.https_proxy_port" } },
  },
}
