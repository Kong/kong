local typedefs = require "kong.db.schema.typedefs"
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
    { run_on = typedefs.run_on_first },
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
