local yaml = require "yaml"
local IO = require "kong.tools.io"
local utils = require "kong.tools.utils"
local logger = require "kong.cli.utils.logger"
local luarocks = require "kong.cli.utils.luarocks"
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

local checks = {
  type = function(value, key_infos, value_type)
    if value_type ~= key_infos.type then
      return "must be a "..key_infos.type
    end
  end,
  minimum = function(value, key_infos, value_type)
    if value_type == "number" and key_infos.min ~= nil and value < key_infos.min then
      return "must be greater than "..key_infos.min
    end
  end,
  enum = function(value, key_infos, value_type)
    if key_infos.enum ~= nil and not utils.table_contains(key_infos.enum, value) then
      return string.format("must be one of: '%s'", table.concat(key_infos.enum, ", "))
    end
  end
}

local function validate_config_schema(config, config_schema)
  if not config_schema then config_schema = config_defaults end
  local errors, property

  for config_key, key_infos in pairs(config_schema) do
    -- Default value
    property = config[config_key]
    if property == nil then
      property = key_infos.default
    end

    -- Recursion on table values
    if key_infos.type == "table" and key_infos.content ~= nil then
      if property == nil then
        property = {}
      end

      local ok, s_errors = validate_config_schema(property, key_infos.content)
      if not ok then
        for s_k, s_v in pairs(s_errors) do
          errors = utils.add_error(errors, config_key.."."..s_k, s_v)
        end
      end
    end

    -- Nullable checking
    if property ~= nil and not key_infos.nullable then
      local property_type = get_type(property, key_infos.type)
      local err
      -- Individual checks
      for _, check_fun in pairs(checks) do
        err = check_fun(property, key_infos, property_type)
        if err then
          errors = utils.add_error(errors, config_key, err)
        end
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
    logger:error("No configuration file at: "..config_path)
    os.exit(1)
  end

  local config = yaml.load(config_contents)

  local ok, errors = _M.validate(config)
  if not ok then
    for config_key, config_error in pairs(errors) do
      if type(config_error) == "table" then
        config_error = table.concat(config_error, ", ")
      end
      logger:warn(string.format("%s: %s", config_key, config_error))
    end
    logger:error("Invalid properties in given configuration file")
    os.exit(1)
  end

  -- Adding computed properties
  config.pid_file = IO.path:join(config.nginx_working_dir, constants.CLI.NGINX_PID)
  config.dao_config = config.databases_available[config.database]
  if config.dns_resolver == "dnsmasq" then
    config.dns_resolver = {
      address = "127.0.0.1:"..config.dns_resolvers_available.dnsmasq.port,
      port = config.dns_resolvers_available.dnsmasq.port,
      dnsmasq = true
    }
  else
    config.dns_resolver = {address = config.dns_resolver.server.address}
  end


  -- Load absolute path for the nginx working directory
  if not stringy.startswith(config.nginx_working_dir, "/") then
    -- It's a relative path, convert it to absolute
    local fs = require "luarocks.fs"
    config.nginx_working_dir = fs.current_dir().."/"..config.nginx_working_dir
  end

  return config, config_path
end

function _M.load_default(config_path)
  if not IO.file_exists(config_path) then
    logger:warn("No configuration at: "..config_path.." using default config instead.")
    config_path = IO.path:join(luarocks.get_config_dir(), "kong.yml")
  end

  logger:info("Using configuration: "..config_path)

  return _M.load(config_path)
end

return _M
