local cjson = require("cjson.safe").new()

cjson.decode_array_with_array_mt(true)

local SUPPORTED_VERSIONS = {
  "kong",       -- first one listed is the default
  "draft4",
}


local PARAM_TYPES = {
  "query",
  "header",
  "path",
}


local SERIALIZATION_STYLES = {
  "label",
  "form",
  "matrix",
  "simple",
  "spaceDelimited",
  "pipeDelimited",
  "deepObject",
}

local ALLOWED_STYLES = {
  header = {
    simple = true,
  },
  path = {
    label = true,
    matrix = true,
    simple = true,
  },
  query = {
    form = true,
    spaceDelimited = true,
    pipeDelimited = true,
    deepObject = true,
  },
}

local DEFAULT_CONTENT_TYPES = {
  "application/json",
}


local function validate_param_schema(entity)
  local validator = require("kong.plugins.request-validator.draft4").validate
  return validator(entity)
end


local function validate_body_schema(entity)
  if not entity.config.body_schema or entity.config.body_schema == ngx.null then
    return true
  end

  local validator = require("kong.plugins.request-validator." ..
                             entity.config.version).validate
  return validator(entity.config.body_schema)
end

local function validate_style(entity)
  if not entity.style or entity.style == ngx.null then
    return true
  end

  if not ALLOWED_STYLES[entity["in"]][entity.style] then
    return false, string.format("style '%s' not supported '%s' parameter",
            entity.style, entity["in"])
  end
  return true
end


return {
  name = "request-validator",

  fields = {
    { config = {
        type = "record",
        fields = {
          { body_schema = {
            type = "string",
            required = false,
          }},
          { allowed_content_types = {
            type = "set",
            default = DEFAULT_CONTENT_TYPES,
            elements = {
              type = "string",
              required = true,
              match = "^[^%s]+%/[^ ;]+$",
            },
          }},
          { version = {
            type = "string",
            one_of = SUPPORTED_VERSIONS,
            default = SUPPORTED_VERSIONS[1],
            required = true,
          }},
          { parameter_schema = {
            type = "array",
            required = false,
            elements = {
              type = "record",
              fields = {
                { ["in"] = { type = "string", one_of = PARAM_TYPES, required = true }, },
                { name = { type = "string", required = true }, },
                { required = { type = "boolean", required = true }, },
                { style = { type = "string", one_of = SERIALIZATION_STYLES}, },
                { explode = { type = "boolean"}, },
                { schema = { type = "string", custom_validator = validate_param_schema }}
              },
              entity_checks = {
                {
                  mutually_required = { "style", "explode", "schema" },
                },
                { custom_entity_check = {
                  field_sources = { "style", "in" },
                  fn = validate_style,
                }},
              }
            },
          }},
        },
        entity_checks = {
          { at_least_one_of = { "body_schema", "parameter_schema" } },
        },
      }
    },
  },
  entity_checks = {
    { custom_entity_check = {
      field_sources = { "config" },
      fn = validate_body_schema,
    }}
  }
}
