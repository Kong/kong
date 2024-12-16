-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local typedefs = require("kong.db.schema.typedefs")
local MetaSchema = require("kong.db.schema.metaschema")
local Plugins = require("kong.db.dao.plugins")
local Errors = require("kong.db.errors").new()


local BUNDLED_PLUGINS_NAMES = require("kong.constants").BUNDLED_PLUGINS_NAMES


local type = type
local sandbox = require("kong.tools.sandbox")
local pcall = pcall
local tostring = tostring


local function compile_chunk(sb, chunk, chunkname)
  local ok, compiled, err = pcall(sb, chunk, chunkname)
  if not ok then
    return nil, compiled
  end
  if err then
    return nil, err
  end

  return compiled
end


local function validate_module(sb, chunk, chunkname)
  local compiled, err = compile_chunk(sb, chunk, chunkname)
  if not compiled then
    return nil, "compilation error (" .. err .. ")"
  end

  local ok, module, err = pcall(compiled)
  if not ok then
    return nil, "load failure (" .. module .. ")"
  end
  if err then
    return nil, "load failure (" .. err .. ")"
  end

  local t = type(module)
  if t ~= "table" then
    return nil, "validation error (expected table, got " .. t .. ")"
  end

  return module
end


local function validate_schema(chunk)
  local schema, err = validate_module(sandbox.sandbox_schema, chunk, "schema")
  if not schema then
    return nil, "schema " .. err
  end

  if schema.name == nil then
    return nil, "schema validation error (missing name)"
  end

  if type(schema.name) ~= "string" then
    return nil, "schema validation error (invalid name)"
  end

  local ok, err = MetaSchema.RestrictedMetaSubSchema:validate(schema)
  if not ok then
    return nil, "schema validation error (" .. tostring(Errors:schema_violation(err)) .. ")"
  end

  return true
end


local function validate_handler(chunk)
  local handler, err = validate_module(sandbox.sandbox_handler, chunk, "handler")
  if not handler then
    return nil, "handler " .. err
  end

  if not Plugins.validate_priority(handler.PRIORITY) then
    return nil, "handler validation error (PRIORITY field is not a valid integer number)"
  end

  if not Plugins.validate_version(handler.VERSION) then
    return nil, "handler validation error (VERSION field does not follow the x.y.z format)"
  end

  if Plugins.implements(handler, "response") and (Plugins.implements(handler, "header_filter") or
                                                  Plugins.implements(handler, "body_filter"))
  then
    return nil, "handler validation error (implementing both response and " ..
                "header_filter/body_filter methods is not allowed)"
  end

  if Plugins.implements(handler, "init_worker") then
    return nil, "handler validation error (implementing init_worker method is not allowed)"
  end

  return true
end


local function validate_name(entity)
  local schema = validate_module(sandbox.sandbox_schema, entity.schema, "schema")
  if not schema or entity.name ~= schema.name then
    return false, "name must be equal to schema.name"
  end
  return true
end


return {
  name = "custom_plugins",
  dao = "kong.db.dao.custom_plugins",
  admin_api_name = "custom-plugins",
  primary_key = { "id" },
  cache_key = { "name" },
  endpoint_key = "name",
  workspaceable = true,
  generate_admin_api = kong.configuration.custom_plugins_enabled,
  fields = {
    { id = typedefs.uuid({
      required = true,
    })},
    { name = {
      type = "string",
      indexed = true,
      required = true,
      unique = true,
      unique_across_ws = true,
      match = [[^[a-z][a-z%d-]-[a-z%d]+$]],
      not_one_of = BUNDLED_PLUGINS_NAMES,
      description = "The name to associate with the given custom plugin.",
    }},
    { schema = {
      type = "string",
      required = true,
      description = "The schema for the given custom plugin.",
      custom_validator = validate_schema,
    }},
    { handler = {
      type = "string",
      required = true,
      description = "The handler for the given custom plugin.",
      custom_validator = validate_handler,
    }},
    { created_at = typedefs.auto_timestamp_s },
    { updated_at = typedefs.auto_timestamp_s },
    { tags = typedefs.tags },
  },
  entity_checks = {
    {
      custom_entity_check = {
        field_sources = { "name", "schema" },
        fn = validate_name,
      },
    },
  },
}
