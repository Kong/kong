-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"


local template_schema = {
  type = "record",
  required = true,
  fields = {
    { name = {
        type = "string",
        description = "Unique name for the template, can be called with `{template://NAME}`",
        required = true,
    }},
    { template = {
        type = "string",
        description = "Template string for this request, supports mustache-style `{{placeholders}}`",
        required = true,
    }},
  }
}


return {
  name = "ai-prompt-template",
  fields = {
    { protocols = typedefs.protocols_http },
    { config = {
      type = "record",
      fields = {
        { templates = {
            description = "Array of templates available to the request context.",
            type = "array",
            elements = template_schema,
            required = true,
        }},
        { allow_untemplated_requests = {
            description = "Set true to allow requests that don't call or match any template.",
            type = "boolean",
            required = true,
            default = true,
        }},
        { log_original_request = {
            description = "Set true to add the original request to the Kong log plugin(s) output.",
            type = "boolean",
            required = true,
            default = false,
        }},
        { max_request_body_size = {
            type = "integer",
            default = 8 * 1024,
            gt = 0,
            description = "max allowed body size allowed to be introspected",
        }},
      }
    }}
  },
}
