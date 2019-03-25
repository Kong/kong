local NewErrors = require "kong.db.errors"
local metaschema = require "kong.plugins.request-validator.metaschema"
local utils = require "kong.plugins.request-validator.utils"


local gen_schema = utils.gen_schema


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
        },
      }
    },
  },

  entity_checks = {
    { custom_entity_check = {
      field_sources = { "config" },
      fn = function(entity)
        local schema, err = gen_schema(entity.config.body_schema)
        if err then
          return false, err
        end

        -- validate against metaschema
        local ok
        ok, err = metaschema:validate(schema)
        if not ok then
          return false, NewErrors:schema_violation(err)
        end

      return true
    end
    }},
  }
}
