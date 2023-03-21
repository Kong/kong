-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"
local spec_parser = require("kong.plugins.oas-validation.utils.spec_parser")

local function validate_spec(entity)
  return spec_parser.load_spec(entity)
end

return {
  name = "oas-validation",
  fields = {
    { protocols = typedefs.protocols_http },
    { config = {
      type = "record",
      fields = {
          { api_spec = { type = "string", custom_validator = validate_spec, required = true } },
          { verbose_response = {type = "boolean", default = false, required = false } },
          { validate_request_body = {type = "boolean", default = true, required = false } },
          { notify_only_request_validation_failure = {type = "boolean", default = false, required = false } },
          { validate_request_header_params = {type = "boolean", default = true, required = false } },
          { validate_request_query_params = {type = "boolean", default = true, required = false } },
          { validate_request_uri_params = {type = "boolean", default = true, required = false } },
          { validate_response_body = {type = "boolean", default = false, required = false } },
          { notify_only_response_body_validation_failure = {type = "boolean", default = false, required = false } },
          { query_parameter_check = {type = "boolean", default = false, required = true } },
          { header_parameter_check = {type = "boolean", default = false, required = true } },
          { allowed_header_parameters = {type = "string",
              default = "Host,Content-Type,User-Agent,Accept,Content-Length", required = false } },
        },
      },
    },
  },
}
