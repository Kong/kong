-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"
local swagger_parser = require "kong.enterprise_edition.openapi.plugins.swagger-parser.parser"
local version = require "version"

local function check_for_config(config)
  local api_spec = config.api_spec
  if config.api_spec_encoded then
    api_spec = ngx.unescape_uri(api_spec)
  end

  local spec ,err = swagger_parser.parse(api_spec)
  if not spec then
    return false, "api_spec: " .. err
  end

  -- only 3.0.x and 3.1.x are allowed
  if spec.spec.openapi and
    (version(spec.spec.openapi) < version("3.0.0") or
     version(spec.spec.openapi) >= version("3.2.0")) then
    return false, "api_spec: invalid spec version: only 3.0.x and 3.1.x are allowed"
  end

  return true
end

return {
  name = "oas-validation",
  fields = {
    { protocols = typedefs.protocols_http },
    { consumer_group = typedefs.no_consumer_group },
    { config = {
      type = "record",
      fields = {
          { api_spec = { description = "The API specification defined using either Swagger or the OpenAPI. This can be either a JSON or YAML based file. If using a YAML file, the spec needs to be URI-Encoded to preserve the YAML format.", type = "string", required = true } },
          { verbose_response = { description = "If set to true, returns a detailed error message for invalid requests & responses. This is useful while testing.", type = "boolean", default = false, required = false } },
          { validate_request_body = { description = "If set to true, validates the request body content against the API specification.", type = "boolean", default = true, required = false } },
          { notify_only_request_validation_failure = { description = "If set to true, notifications via event hooks are enabled, but request based validation failures don't affect the request flow.", type = "boolean", default = false, required = false } },
          { validate_request_header_params = { description = "If set to true, validates HTTP header parameters against the API specification.", type = "boolean", default = true, required = false } },
          { validate_request_query_params = { description = "If set to true, validates query parameters against the API specification.", type = "boolean", default = true, required = false } },
          { validate_request_uri_params = { description = "If set to true, validates URI parameters in the request against the API specification.", type = "boolean", default = true, required = false } },
          { validate_response_body = { description = "If set to true, validates the response from the upstream services against the API specification. If validation fails, it results in an `HTTP 406 Not Acceptable` status code.", type = "boolean", default = false, required = false } },
          { notify_only_response_body_validation_failure = { description = "If set to true, notifications via event hooks are enabled, but response validation failures don't affect the response flow.", type = "boolean", default = false, required = false } },
          { query_parameter_check = { description = "If set to true, checks if query parameters in the request exist in the API specification.", type = "boolean", default = false, required = true } },
          { header_parameter_check = { description = "If set to true, checks if HTTP header parameters in the request exist in the API specification.", type = "boolean", default = false, required = true } },
          { allowed_header_parameters = { description = "List of header parameters in the request that will be ignored when performing HTTP header validation. These are additional headers added to an API request beyond those defined in the API specification.  For example, you might include the HTTP header `User-Agent`, which lets servers and network peers identify the application, operating system, vendor, and/or version of the requesting user agent.", type = "string",
              default = "Host,Content-Type,User-Agent,Accept,Content-Length", required = false } },
          { include_base_path = { description = "Indicates whether to include the base path when performing path match evaluation.", type = "boolean", default = false, required = true } },
          { api_spec_encoded = { description = "Indicates whether the api_spec is URI-Encoded.", type = "boolean", default = true, required = true } },
          { custom_base_path = typedefs.path { description = "The base path to be used for path match evaluation. This value is ignored if `include_base_path` is set to `false`.", required = false } },
        },
      custom_validator = check_for_config,
      },
    },
  },
}
