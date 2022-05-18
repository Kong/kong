local MetaSchema = require "kong.db.schema.metaschema"
local Entity = require "kong.db.schema.entity"
local utils = require "kong.tools.utils"


local tostring = tostring


local vault_loader = {}


function vault_loader.load_subschema(parent_schema, vault, errors)
  local vault_schema = "kong.vaults." .. vault .. ".schema"
  local ok, schema = utils.load_module_if_exists(vault_schema)
  if not ok then
    return nil, "no configuration schema found for vault: " .. vault
  end

  local err_t
  ok, err_t = MetaSchema.MetaSubSchema:validate(schema)
  if not ok then
    return nil, tostring(errors:schema_violation(err_t))
  end

  local err
  ok, err = Entity.new_subschema(parent_schema, vault, schema)
  if not ok then
    return nil, "error initializing schema for vault: " .. err
  end

  return schema
end


return vault_loader
