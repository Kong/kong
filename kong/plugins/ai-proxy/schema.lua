local typedefs = require "kong.db.schema.typedefs"

local auth_schema = {
  type = "record",
  required = false,
  fields = {
    { header_name = { type = "string", description = "If AI model requires authentication via Authorization or API key header, specify its name here.", required = false, referenceable = true } },
    { header_value = { type = "string", description = "Specify the full auth header value for 'header_name', for example 'Bearer key' or just 'key'.", required = false, referenceable = true } },
    { param_name = { type = "string", description = "If AI model requires authentication via query parameter, specify its name here.", required = false, referenceable = true } },
    { param_value = { type = "string", description = "Specify the full parameter value for 'param_name'.", required = false, referenceable = true } },
    { param_location = { type = "string", description = "Specify whether the 'param_name' and 'param_value' options go in a query string, or the POST form/JSON body.", required = false, one_of = { "query", "body" } } },
  }
}

local model_options_schema = {
  description = "Key/value settings for the model",
  type = "record",
  required = false,
  fields = {
    { max_tokens = { type = "integer", description = "Defines the max_tokens, if using chat or completion models.", required = false, default = 256 } },
    { temperature = { type = "number", description = "Defines the matching temperature, if using chat or completion models.", required = false, between = { 0.0, 5.0 }, default = 1.0 } },
    { top_p = { type = "number", description = "Defines the top-p probability mass, if supported.", required = false, between = { 0, 1 }, default = 1.0 } },
    { top_k = { type = "integer", description = "Defines the top-k most likely tokens, if supported.", required = false,between = { 0, 500 }, default = 0 } },
    { anthropic_version = { type = "string", description = "Defines the schema/API version, if using Anthropic provider.", required = false } },
    { azure_instance = { type = "string", description = "Instance name for Azure OpenAI hosted models.", required = false } },
    { llama2_format = { type = "string", description = "If using llama2 provider, select the upstream message format.", required = false, one_of = { "raw", "openai"} } },
    { upstream_url = typedefs.url { description = "Manually specify or override the full URL to the AI operation endpoints, when calling (self-)hosted models, or for running via a private endpoint.", required = false } },
  }
}

local model_schema = {
  type = "record",
  required = true,
  fields = {
    { provider = { type = "string", description = "AI provider request format - Kong translates requests to and from the specified backend compatible formats.", required = true, one_of = { "openai", "azure", "anthropic", "cohere", "mistral", "llama2", "preserve" }, default = "openai" } },
    { name = { type = "string", description = "Model name to execute.", required = true, } },
    { options = model_options_schema },
  }
}

local logging_schema = {
  type = "record",
  required = true,
  fields = {
    { log_statistics = { type = "boolean", description = "If enabled and supported by the driver, will add model usage and token metrics into the Kong log plugin(s) output.", required = true, default = true } },
    { log_payloads = { type = "boolean", description = "If enabled, will log the request and response body into the Kong log plugin(s) output.", required = true, default = false } },
  }
}

return {
  name = "ai-proxy",
  fields = {
    { protocols = typedefs.protocols_http },
    { consumer = typedefs.no_consumer },
    { service = typedefs.no_service },
    { config = {
      type = "record",
      fields = {
        { route_type = { type = "string", description = "The model's operation implementation, for this provider.", required = true, one_of = { "llm/v1/chat", "llm/v1/completions" } } },
        { auth = auth_schema },
        { model = model_schema },
        { logging = logging_schema },
      }
    }}
  },
  entity_checks = {
    -- these three checks run in a chain, to ensure that all auth params for each respective "set" are specified
    { conditional_at_least_one_of = { if_field = "config.model.provider",
                                      if_match = { one_of = { "openai", "azure", "anthropic", "cohere" } },
                                      then_at_least_one_of = { "config.auth.header_name", "config.auth.param_name" },
                                      then_err = "must set one of %s, and its respective options, when provider is not self-hosted" }},
    { mutually_required = { "config.auth.header_name", "config.auth.header_value" }, },
    { mutually_required = { "config.auth.param_name", "config.auth.param_value", "config.auth.param_location" }, },

    { conditional_at_least_one_of = { if_field = "config.model.provider",
                                      if_match = { one_of = { "anthropic" } },
                                      then_at_least_one_of = { "config.model.options.anthropic_version" },
                                      then_err = "must set %s for anthropic provider" }},

    { conditional_at_least_one_of = { if_field = "config.model.provider",
                                      if_match = { one_of = { "azure" } },
                                      then_at_least_one_of = { "config.model.options.azure_instance" },
                                      then_err = "must set %s for azure provider" }},

    { conditional_at_least_one_of = { if_field = "config.model.provider",
                                      if_match = { one_of = { "mistral", "llama2" } },
                                      then_at_least_one_of = { "config.model.options.upstream_url" },
                                      then_err = "must set %s for self-hosted providers/models" }},

  },
}
