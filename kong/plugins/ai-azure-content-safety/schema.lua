-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"

local plugin_name = "ai-azure-content-safety"

local categories_schema = {
  type = "record",
  required = true,
  fields = {
    { name = {
        type = "string",
        required = true }},
    { rejection_level = {
        type = "integer",
        required = true }},
  },
}

local schema = {
  name = plugin_name,
  fields = {
    -- the 'fields' array is the top-level entry with fields defined by Kong
    { protocols = typedefs.protocols_http },
    { consumer = typedefs.no_consumer },
    { consumer_group = typedefs.no_consumer_group },
    {
      config = {
        type = "record",
        fields = {
          { content_safety_url = typedefs.url {
              description = "Full URL, inc protocol, of the Azure Content Safety instance.",
              required = true,
              referenceable = true }},
          { azure_api_version = {
              description = "Sets the ?api-version URL parameter, used for defining " .. 
                            "the Azure Content Services interchange format.",
              type = "string",
              required = true,
              default = "2023-10-01",
              len_min = 1 }},
          { azure_use_managed_identity = {
              description = "If checked, uses (if set) `azure_client_id`, " ..
                            "`azure_client_secret`, and/or `azure_tenant_id` for Azure " .. 
                            "authentication, via Managed or User-assigned identity",
              type = "boolean",
              default = false }},
          { azure_client_id = {
              description = "If `azure_use_managed_identity` is true, set the client ID if required.",
              type = "string",
              required = false }},
          { azure_client_secret = {
              description = "If `azure_use_managed_identity` is true, set the client secret if required.",
              type = "string",
              required = false }},
          { azure_tenant_id = {
              description = "If `azure_use_managed_identity` is true, set the tenant ID if required.",
              type = "string",
              required = false }},
          { content_safety_key = {
              description = "If `azure_use_managed_identity` is true, set the API key to call Content Safety.",
              type = "string",
              required = false,
              referenceable = true,
              encrypted = true }},
          { text_source = {
              description = "Select where to pick the 'text' for the Azure Content " .. 
                            "Services request.",
              type = "string",
              default = "concatenate_all_content",
              one_of = {
                "concatenate_all_content",
                "concatenate_user_content",
              }}},
          { categories = {
              description = "Array of categories, and their thresholds, to measure on.",
              type = "array",
              elements = categories_schema }},
          { reveal_failure_reason = {
              description = "Set true to tell the caller why their request was rejected, if so.",
              type = "boolean",
              default = true }},
          { output_type = {
              description = "See https://learn.microsoft.com/en-us/azure/ai-services/openai" .. 
                            "/concepts/content-filter#content-filtering-categories",
              type = "string",
              default = "FourSeverityLevels",
              one_of = { "FourSeverityLevels", "EightSeverityLevels" } }},
          { blocklist_names = {
              description = "Use these configured blocklists (in Azure Content Services) " ..
                            "when inspecting content.",
              type = "array",
              elements = { type = "string" } }},
          { halt_on_blocklist_hit = {
              description = "Tells Azure to reject the request if any blocklist filter is hit.",
              type = "boolean",
              default = true }},
        },
      },
    },
  },
}

return schema
