-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local MetaSchema = require "kong.db.schema.metaschema"
local Entity = require "kong.db.schema.entity"
local load_module_if_exists = require "kong.tools.module".load_module_if_exists


local tostring = tostring


local vault_loader = {}


function vault_loader.load_subschema(parent_schema, vault, errors)
  local vault_schema = "kong.vaults." .. vault .. ".schema"
  local ok, schema = load_module_if_exists(vault_schema)
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
