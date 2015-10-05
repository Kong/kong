local yaml = require "yaml"
local IO = require "kong.tools.io"
local utils = require "kong.tools.utils"
local cutils = require "kong.cli.utils"
local stringy = require "stringy"
local constants = require "kong.constants"
local config_defaults = require "kong.tools.config_defaults"

local function get_type(value, val_type)
  if val_type == "array" and utils.is_array(value) then
    return "array"
  else
    return type(value)
  end
end

local function validate_config_schema(config, config_schema)
  if not config_schema then config_schema = config_defaults end
  local errors, property

  for config_key, key_infos in pairs(config_schema) do
    -- Default value
    property = config[config_key] or key_infos.default

    -- Recursion on table values
    if key_infos.type == "table" and key_infos.content ~= nil then
      if property == nil then
        property = {}
      end

      local ok, s_errors = validate_config_schema(property, key_infos.content)
      if not ok then
        --errors = utils.add_error(errors, config_key, s_errors)
        for s_k, s_v in pairs(s_errors) do
          errors = utils.add_error(errors, config_key.."."..s_k, s_v)
        end
      end
    end

    -- Nullable checking
    if property ~= nil and not key_infos.nullable then
      local property_type = get_type(property, key_infos.type)
      -- Type checking
      if property_type ~= key_infos.type then
        errors = utils.add_error(errors, config_key, "must be a "..key_infos.type)
      end
      -- Min checking
      if property_type == "number" and key_infos.min ~= nil and property < key_infos.min then
        errors = utils.add_error(errors, config_key, "must be greater than "..key_infos.min)
      end
    end

    config[config_key] = property
  end

  return errors == nil, errors
end

local _M = {}

function _M.validate(config)
  local ok, errors = validate_config_schema(config)
  if not ok then
    return false, errors
  end

  -- Check selected database
  if config.databases_available[config.database] == nil then
    return false, {database = config.database.." is not listed in databases_available"}
  end

  return true
end

function _M.load(config_path)
  local config_contents = IO.read_file(config_path)
  if not config_contents then
    cutils.logger:error_exit("No configuration file at: "..config_path)
  end

  local config = yaml.load(config_contents)

  local ok, errors = _M.validate(config)
  if not ok then
    for config_key, config_error in pairs(errors) do
      cutils.logger:warn(string.format("%s: %s", config_key, config_error))
    end
    cutils.logger:error_exit("Invalid properties in given configuration file")
  end

  -- Adding computed properties
  config.pid_file = IO.path:join(config.nginx_working_dir, constants.CLI.NGINX_PID)
  config.dao_config = config.databases_available[config.database]

  -- Load absolute path for the nginx working directory
  if not stringy.startswith(config.nginx_working_dir, "/") then
    -- It's a relative path, convert it to absolute
    local fs = require "luarocks.fs"
    config.nginx_working_dir = fs.current_dir().."/"..config.nginx_working_dir
  end

  return config
end

return _M
