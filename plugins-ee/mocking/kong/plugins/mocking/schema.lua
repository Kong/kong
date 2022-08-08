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

return {
  name = "mocking",
  fields = {
    { config = {
      type = "record",
      fields = {
        { api_specification_filename = { type = "string", required = false } },
        { api_specification = { type = "string", required = false, custom_validator = validate_specification } },
        { random_delay = { type = "boolean", default = false } },
        { max_delay_time = { type = "number", default = 1 } },
        { min_delay_time = { type = "number", default = 0.001 } },
        -- this causes to randomly select one example if multiple examples
        -- are present.
        { random_examples = { type = "boolean", default = false } },
        { included_status_codes = { type = "array", elements = { type = "integer" } } },
        { random_status_code = { type = "boolean", required = true, default = false } },
        { behavioral_headers = {
          type = "record",
          fields = {
            { delay = { type = "string", required = true, default = 'X-Kong-Mocking-Delay' } },
            { example_id = { type = "string", required = true, default = 'X-Kong-Mocking-Example-Id' } },
            { status_code = { type = "string", required = true, default = 'X-Kong-Mocking-Status-Code' } },
          }
        } },
      }
    } },
  },
  entity_checks = {
    { at_least_one_of = { "config.api_specification_filename", "config.api_specification" } },
  }
}
