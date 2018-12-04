local NewErrors = require "kong.db.errors"
local OldErrors = require "kong.dao.errors"
local metaschema = require "kong.plugins.request-validator.metaschema"
local utils = require "kong.plugins.request-validator.utils"


local gen_schema = utils.gen_schema


return {
  fields = {
    body_schema = {
      type = "string",
      required = true,
    }
  },
  self_check = function(schema, plugin_t, dao, is_updating)
    local schema, err = gen_schema(plugin_t.body_schema)
    if err then
      return false, OldErrors.schema(err)
    end

    -- validate against metaschema
    local ok
    ok, err = metaschema:validate(schema)
    if not ok then
      return false, NewErrors:schema_violation(err)
    end

    return true
  end
}
