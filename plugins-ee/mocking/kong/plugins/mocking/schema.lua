-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local cjson = require("cjson.safe").new()
local lyaml = require "lyaml"

local function validate_specification(spec_content)
  local parsed_spec, _ = cjson.decode(spec_content)
  if type(parsed_spec) ~= "table" then
    local pok
    pok, parsed_spec = pcall(lyaml.load, spec_content)
    if not pok or type(parsed_spec) ~= "table" then
      return false, "api_specification is neither valid json nor valid yaml"
    end
  end
  return true
end

local typedefs  = require "kong.db.schema.typedefs"

return {
  name = "mocking",
  fields = {
    { protocols = typedefs.protocols_http },
    { consumer_group = typedefs.no_consumer_group },
    { config = {
      type = "record",
      fields = {
        { api_specification_filename = { description = "The path and name of the specification file loaded into Kong Gateway's database. You cannot use this option for DB-less or hybrid mode.", type = "string", required = false } },
        { api_specification = { description = "The contents of the specification file. You must use this option for hybrid or DB-less mode. You can include the full specification as part of the configuration. In Kong Manager, you can copy and paste the contents of the spec directly into the `Config.Api Specification` text field.", type = "string", required = false, custom_validator = validate_specification } },
        { random_delay = { description = "Enables a random delay in the mocked response. Introduces delays to simulate real-time response times by APIs.", type = "boolean", default = false } },
        { max_delay_time = { description = "The maximum value in seconds of delay time. Set this value when `random_delay` is enabled and you want to adjust the default. The value must be greater than the `min_delay_time`.", type = "number", default = 1 } },
        { min_delay_time = { description = "The minimum value in seconds of delay time. Set this value when `random_delay` is enabled and you want to adjust the default. The value must be less than the `max_delay_time`.", type = "number", default = 0.001 } },
        -- this causes to randomly select one example if multiple examples
        -- are present.
        { random_examples = { description = "Randomly selects one example and returns it. This parameter requires the spec to have multiple examples configured.", type = "boolean", default = false } },
        { included_status_codes = { description = "A global list of the HTTP status codes that can only be selected and returned.", type = "array", elements = { type = "integer" } } },
        { random_status_code = { description = "Determines whether to randomly select an HTTP status code from the responses of the corresponding API method. The default value is `false`, which means the minimum HTTP status code is always selected and returned.", type = "boolean", required = true, default = false } },
        { include_base_path = { description = "Indicates whether to include the base path when performing path match evaluation.", type = "boolean", required = true, default = false } },
      }
    } },
  },
  entity_checks = {
    { at_least_one_of = { "config.api_specification_filename", "config.api_specification" } },
  }
}
