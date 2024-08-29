local MetaSchema = require "kong.db.schema.metaschema"
local Entity = require "kong.db.schema.entity"
local load_module_if_exists = require "kong.tools.module".load_module_if_exists


local tostring = tostring


local SUBSCHEMA_CACHE = setmetatable({}, { __mode = "kv" })


local vault_loader = {}


function vault_loader.load_subschema(parent_schema, vault, errors)
  local schema = SUBSCHEMA_CACHE[vault]
  if not schema then
    local ok
    ok, schema = load_module_if_exists("kong.vaults." .. vault .. ".schema")
    if not ok then
      return nil, "no configuration schema found for vault: " .. vault
    end

    local err_t
    ok, err_t = MetaSchema.MetaSubSchema:validate(schema)
    if not ok then
      return nil, tostring(errors:schema_violation(err_t))
    end

    SUBSCHEMA_CACHE[vault] = schema
  end

  if not SUBSCHEMA_CACHE[parent_schema] then
    SUBSCHEMA_CACHE[parent_schema] = {}
  end

  if not SUBSCHEMA_CACHE[parent_schema][vault] then
    SUBSCHEMA_CACHE[parent_schema][vault] = true
    local ok, err = Entity.new_subschema(parent_schema, vault, schema)
    if not ok then
      return nil, "error initializing schema for vault: " .. err
    end
  end

  return schema
end


return vault_loader
