-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

return {
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
    -- [[ EE
    {
      azure_use_managed_identity = {
        type = "boolean",
        description =
        "Set true to use the Azure Cloud Managed Identity (or user-assigned identity) to authenticate with Azure-provider models.",
        required = false,
        default = false
      }
    },
    {
      azure_client_id = {
        type = "string",
        description =
        "If azure_use_managed_identity is set to true, and you need to use a different user-assigned identity for this LLM instance, set the client ID.",
        required = false,
        referenceable = true
      }
    },
    {
      azure_client_secret = {
        type = "string",
        description =
        "If azure_use_managed_identity is set to true, and you need to use a different user-assigned identity for this LLM instance, set the client secret.",
        required = false,
        encrypted = true,  -- [[ ee declaration ]]
        referenceable = true,
      }
    },
    {
      azure_tenant_id = {
        type = "string",
        description =
        "If azure_use_managed_identity is set to true, and you need to use a different user-assigned identity for this LLM instance, set the tenant ID.",
        required = false,
        referenceable = true
      }
    },
    -- EE ]]
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
        encrypted = true,  -- [[ ee declaration ]]
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
    { allow_auth_override = {
        type = "boolean",
        description = "If enabled, the authorization header or parameter can be overridden in the request by the value configured in the plugin.",
        required = false,
        default = true }},
  }
}
