-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local validators = require("kong.plugins.request-validator.validators")
local cjson = require("cjson.safe").new()
local typedefs = require "kong.db.schema.typedefs"
local mime_type = require "kong.tools.mime_type"
local nkeys = require "table.nkeys"

local parse_mime_type = mime_type.parse_mime_type

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
  local validator = require(validators.draft4).validate
  return validator(entity, true)
end


local function validate_body_schema(entity)
  if not entity.config.body_schema or entity.config.body_schema == ngx.null then
    return true
  end

  local validator = require(validators[entity.config.version]).validate
  return validator(entity.config.body_schema, false)
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

local function validate_content_type(entity)
  if entity == nil or entity == "" then
    return false, "content type cannot be empty"
  end

  local t, _, params = parse_mime_type(entity)
  if not t then
    return false, "invalid value: " .. entity
  end

  if params and nkeys(params) > 1 then
    -- RFC does not claim the behavior of multiple parameters.
    -- Hence supports only one parameter for now(normally is 'charset').
    return false, "does not support multiple parameters: " .. entity
  end

  return true
end

return {
  name = "request-validator",

  fields = {
    { protocols = typedefs.protocols_http },
    { consumer_group = typedefs.no_consumer_group },
    { config = {
        type = "record",
        fields = {
          { body_schema = { description = "The request body schema specification. One of `body_schema` or `parameter_schema` must be specified.", type = "string",
            required = false,
          }},
          { allowed_content_types = { description = "List of allowed content types. The value can be configured with the `charset` parameter. For example, `application/json; charset=UTF-8`.", type = "set",
            default = DEFAULT_CONTENT_TYPES,
            elements = { type = "string",
              required = true,
              custom_validator = validate_content_type,
            },
          }},
          { version = { description = "Which validator to use. Supported values are `kong` (default) for using Kong's own schema validator, or `draft4` for using a JSON Schema Draft 4-compliant validator.", type = "string",
            one_of = SUPPORTED_VERSIONS,
            default = SUPPORTED_VERSIONS[1],
            required = true,
          }},
          { parameter_schema = { description = "Array of parameter validator specification. One of `body_schema` or `parameter_schema` must be specified.", type = "array",
            required = false,
            elements = {
              type = "record",
              fields = {
                { ["in"] = { description = "The location of the parameter.",
                  type = "string", one_of = PARAM_TYPES, required = true }, },
                { name = { description = "The name of the parameter. Parameter names are case-sensitive, and correspond to the parameter name used by the `in` property. If `in` is `path`, the `name` field MUST correspond to the named capture group from the configured `route`.",
                  type = "string", required = true }, },
                { required = { description = "Determines whether this parameter is mandatory.",
                  type = "boolean", required = true }, },
                { style = { description = "Required when `schema` and `explode` are set. Describes how the parameter value will be deserialized depending on the type of the parameter value.",
                  type = "string", one_of = SERIALIZATION_STYLES}, },
                { explode = { description = "Required when `schema` and `style` are set. When `explode` is `true`, parameter values of type `array` or `object` generate separate parameters for each value of the array or key-value pair of the map. For other types of parameters, this property has no effect.",
                  type = "boolean"}, },
                { schema = { description = "Requred when `style` and `explode` are set. This is the schema defining the type used for the parameter. It is validated using `draft4` for JSON Schema draft 4 compliant validator. In addition to being a valid JSON Schema, the parameter schema MUST have a top-level `type` property to enable proper deserialization before validating.",
                  type = "string", custom_validator = validate_param_schema }}
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
          { verbose_response = { description = "If enabled, the plugin returns more verbose and detailed validation errors.", type = "boolean",
            default = false,
            required = true,
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
