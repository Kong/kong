
local SUPPORTED_VERSIONS = {
  "kong",       -- first one listed is the default
  "draft4",
}

local function validate_schema(entity)
  local validator = require("kong.plugins.request-validator." ..
                             entity.config.version).validate

  return validator(entity)
end

return {
  name = "request-validator",

  fields = {
    { config = {
        type = "record",
        fields = {
          { body_schema = {
            type = "string",
            required = true,
          }},
          { version = {
              type = "string",
              one_of = SUPPORTED_VERSIONS,
              default = SUPPORTED_VERSIONS[1],
              required = true,
          }},
        },
      }
    },
  },

  entity_checks = {
    { custom_entity_check = {
      field_sources = { "config" },
      fn = validate_schema,
    }},
  }
}
