local typedefs = require("kong.db.schema.typedefs")
local fmt = string.format


local bedrock_options_schema = {
  type = "record",
  required = false,
  fields = {
    { aws_region = {
      description = "If using AWS providers (Bedrock) you can override the `AWS_REGION` " ..
                    "environment variable by setting this option.",
      type = "string",
      required = false }},
  },
}


local gemini_options_schema = {
  type = "record",
  required = false,
  fields = {
    { api_endpoint = {
        type = "string",
        description = "If running Gemini on Vertex, specify the regional API endpoint (hostname only).",
        required = false }},
    { project_id = {
        type = "string",
        description = "If running Gemini on Vertex, specify the project ID.",
        required = false }},
    { location_id = {
        type = "string",
        description = "If running Gemini on Vertex, specify the location ID.",
        required = false }},
  },
  entity_checks = {
    { mutually_required = { "api_endpoint", "project_id", "location_id" }, },
  },
}


local auth_schema = {
  type = "record",
  required = false,
  fields = {
    { header_name = {
        type = "string",
        description = "If AI model requires authentication via Authorization or API key header, specify its name here.",
        required = false,
        referenceable = true }},
    { header_value = {
        type = "string",
        description = "Specify the full auth header value for 'header_name', for example 'Bearer key' or just 'key'.",
        required = false,
        encrypted = true,  -- [[ ee declaration ]]
        referenceable = true }},
    { param_name = {
        type = "string",
        description = "If AI model requires authentication via query parameter, specify its name here.",
        required = false,
        referenceable = true }},
    { param_value = {
        type = "string",
        description = "Specify the full parameter value for 'param_name'.",
        required = false,
        encrypted = true,  -- [[ ee declaration ]]
        referenceable = true }},
    { param_location = {
        type = "string",
        description = "Specify whether the 'param_name' and 'param_value' options go in a query string, or the POST form/JSON body.",
        required = false,
        one_of = { "query", "body" } }},
    { gcp_use_service_account = {
        type = "boolean",
        description = "Use service account auth for GCP-based providers and models.",
        required = false,
        default = false }},
    { gcp_service_account_json = {
        type = "string",
        description = "Set this field to the full JSON of the GCP service account to authenticate, if required. " ..
                      "If null (and gcp_use_service_account is true), Kong will attempt to read from " ..
                      "environment variable `GCP_SERVICE_ACCOUNT`.",
        required = false,
        referenceable = true }},
    { aws_access_key_id = {
        type = "string",
        description = "Set this if you are using an AWS provider (Bedrock) and you are authenticating " ..
                      "using static IAM User credentials. Setting this will override the AWS_ACCESS_KEY_ID " ..
                      "environment variable for this plugin instance.",
        required = false,
        encrypted = true,
        referenceable = true }},
    { aws_secret_access_key = {
        type = "string",
        description = "Set this if you are using an AWS provider (Bedrock) and you are authenticating " ..
                      "using static IAM User credentials. Setting this will override the AWS_SECRET_ACCESS_KEY " ..
                      "environment variable for this plugin instance.",
        required = false,
        encrypted = true,
        referenceable = true }},
    { allow_override = {
        type = "boolean",
        description = "If enabled, the authorization header or parameter can be overridden in the request by the value configured in the plugin.",
        required = false,
        default = false }},
  }
}


local model_options_schema = {
  description = "Key/value settings for the model",
  type = "record",
  required = false,
  fields = {
    { max_tokens = {
        type = "integer",
        description = "Defines the max_tokens, if using chat or completion models.",
        required = false,
        default = 256 }},
    { input_cost = {
        type = "number",
        description = "Defines the cost per 1M tokens in your prompt.",
        required = false,
        gt = 0}},
    { output_cost = {
        type = "number",
        description = "Defines the cost per 1M tokens in the output of the AI.",
        required = false,
        gt = 0}},
    { temperature = {
        type = "number",
        description = "Defines the matching temperature, if using chat or completion models.",
        required = false,
        between = { 0.0, 5.0 }}},
    { top_p = {
        type = "number",
        description = "Defines the top-p probability mass, if supported.",
        required = false,
        between = { 0, 1 }}},
    { top_k = {
        type = "integer",
        description = "Defines the top-k most likely tokens, if supported.",
        required = false,
        between = { 0, 500 }}},
    { anthropic_version = {
        type = "string",
        description = "Defines the schema/API version, if using Anthropic provider.",
        required = false }},
    { azure_instance = {
        type = "string",
        description = "Instance name for Azure OpenAI hosted models.",
        required = false }},
    { azure_api_version = {
        type = "string",
        description = "'api-version' for Azure OpenAI instances.",
        required = false,
        default = "2023-05-15" }},
    { azure_deployment_id = {
        type = "string",
        description = "Deployment ID for Azure OpenAI instances.",
        required = false }},
    { llama2_format = {
        type = "string",
        description = "If using llama2 provider, select the upstream message format.",
        required = false,
        one_of = { "raw", "openai", "ollama" }}},
    { mistral_format = {
        type = "string",
        description = "If using mistral provider, select the upstream message format.",
        required = false,
        one_of = { "openai", "ollama" }}},
    { upstream_url = typedefs.url {
        description = "Manually specify or override the full URL to the AI operation endpoints, "
                   .. "when calling (self-)hosted models, or for running via a private endpoint.",
        required = false }},
    { upstream_path = {
        description = "Manually specify or override the AI operation path, "
                   .. "used when e.g. using the 'preserve' route_type.",
        type = "string",
        required = false }},
    { gemini = gemini_options_schema },
    { bedrock = bedrock_options_schema },
  }
}



local model_schema = {
  type = "record",
  required = true,
  fields = {
    { provider = {
        type = "string", description = "AI provider request format - Kong translates "
                                    .. "requests to and from the specified backend compatible formats.",
        required = true,
        one_of = { "openai", "azure", "anthropic", "cohere", "mistral", "llama2", "gemini", "bedrock" }}},
    { name = {
        type = "string",
        description = "Model name to execute.",
        required = false }},
    { options = model_options_schema },
  }
}



local logging_schema = {
  type = "record",
  required = true,
  fields = {
    { log_statistics = {
        type = "boolean",
        description = "If enabled and supported by the driver, "
                   .. "will add model usage and token metrics into the Kong log plugin(s) output.",
                   required = true,
                   default = false }},
    { log_payloads = {
        type = "boolean",
        description = "If enabled, will log the request and response body into the Kong log plugin(s) output.",
        required = true, default = false }},
  }
}



local UNSUPPORTED_LOG_STATISTICS = {
  ["llm/v1/completions"] = { ["anthropic"] = true },
}



return {
  type = "record",
  fields = {
    { route_type = {
        type = "string",
        description = "The model's operation implementation, for this provider. " ..
                      "Set to `preserve` to pass through without transformation.",
        required = true,
        one_of = { "llm/v1/chat", "llm/v1/completions", "preserve" } }},
    { auth = auth_schema },
    { model = model_schema },
    { logging = logging_schema },
  },
  entity_checks = {
    { conditional =  { if_field = "model.provider",
                          if_match = { one_of = { "bedrock", "gemini" } },
                          then_field = "auth.allow_override",
                          then_match = { eq = false },
                          then_err = "bedrock and gemini only support auth.allow_override = false" }},
    { mutually_required = { "auth.header_name", "auth.header_value" }, },
    { mutually_required = { "auth.param_name", "auth.param_value", "auth.param_location" }, },

    { conditional_at_least_one_of = { if_field = "model.provider",
                                      if_match = { one_of = { "llama2" } },
                                      then_at_least_one_of = { "model.options.llama2_format" },
                                      then_err = "must set %s for llama2 provider" }},

    { conditional_at_least_one_of = { if_field = "model.provider",
                                      if_match = { one_of = { "mistral" } },
                                      then_at_least_one_of = { "model.options.mistral_format" },
                                      then_err = "must set %s for mistral provider" }},

    { conditional_at_least_one_of = { if_field = "model.provider",
                                      if_match = { one_of = { "anthropic" } },
                                      then_at_least_one_of = { "model.options.anthropic_version" },
                                      then_err = "must set %s for anthropic provider" }},

    { conditional_at_least_one_of = { if_field = "model.provider",
                                      if_match = { one_of = { "azure" } },
                                      then_at_least_one_of = { "model.options.azure_instance" },
                                      then_err = "must set %s for azure provider" }},

    { conditional_at_least_one_of = { if_field = "model.provider",
                                      if_match = { one_of = { "azure" } },
                                      then_at_least_one_of = { "model.options.azure_api_version" },
                                      then_err = "must set %s for azure provider" }},

    { conditional_at_least_one_of = { if_field = "model.provider",
                                      if_match = { one_of = { "azure" } },
                                      then_at_least_one_of = { "model.options.azure_deployment_id" },
                                      then_err = "must set %s for azure provider" }},

    { conditional_at_least_one_of = { if_field = "model.provider",
                                      if_match = { one_of = { "llama2" } },
                                      then_at_least_one_of = { "model.options.upstream_url" },
                                      then_err = "must set %s for self-hosted providers/models" }},

    {
      custom_entity_check = {
        field_sources = { "route_type", "model", "logging" },
        fn = function(entity)
          if entity.logging.log_statistics and UNSUPPORTED_LOG_STATISTICS[entity.route_type]
            and UNSUPPORTED_LOG_STATISTICS[entity.route_type][entity.model.provider] then
              return nil, fmt("%s does not support statistics when route_type is %s",
                               entity.model.provider, entity.route_type)

          else
            return true
          end
        end,
      }
    },
  },
}
