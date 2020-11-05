-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local pl_template = require "pl.template"


local function validate_template(entry)
  local status, res, err = pcall(pl_template.compile, entry)
  if not status or err then
    return false, "value '" .. entry ..
            "' is not in supported format, error:" ..
            (status and res or err)
  end
  return true
end


return {
  name = "route-transformer",
  fields = {
    { config = {
        type = "record",
        fields = {
          { path = {
            type = "string",
            custom_validator = validate_template,
          }},
          { port = {
            type = "string",
            custom_validator = validate_template,
          }},
          { host = {
            type = "string",
            custom_validator = validate_template,
          }},
        },
        entity_checks = {
          { at_least_one_of = { "path", "port", "host" } }
        },
      },
    },
  }
}
