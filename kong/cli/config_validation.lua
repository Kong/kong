local utils = require "kong.tools.utils"
local config_defaults = require "kong.cli.config_defaults"

local function get_type(value, val_type)
  if val_type == "array" and utils.is_array(value) then
    return "array"
  else
    return type(value)
  end
end

local function validate_config(config, config_schema)
  if not config_schema then config_schema = config_defaults end
  local errors, property

  for config_key, key_infos in pairs(config_schema) do
    -- Default value
    property = config[config_key] or key_infos.default

    -- Recursion on table values
    if key_infos.type == "table" then
      if property == nil then
        property = {}
      end

      local ok, s_errors = validate_config(property, key_infos.content)
      if not ok then
        --errors = utils.add_error(errors, config_key, s_errors)
        for s_k, s_v in pairs(s_errors) do
          errors = utils.add_error(errors, config_key.."."..s_k, s_v)
        end
      end
    end

    -- Nullable checking
    if property ~= nil and not key_infos.nullable then
      -- Type checking
      if get_type(property, key_infos.type) ~= key_infos.type then
        errors = utils.add_error(errors, config_key, "must be a "..key_infos.type)
      end
    end

    config[config_key] = property
  end

  return errors == nil, errors
end

return validate_config
