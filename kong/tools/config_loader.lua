local yaml = require "yaml"
local IO = require "kong.tools.io"
local utils = require "kong.tools.utils"
local logger = require "kong.cli.utils.logger"
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

local function is_valid_IPv4(ip)
  if not ip or stringy.strip(ip) == "" then return false end

  local a, b, c, d = ip:match("^(%d%d?%d?)%.(%d%d?%d?)%.(%d%d?%d?)%.(%d%d?%d?)$")
  a = tonumber(a)
  b = tonumber(b)
  c = tonumber(c)
  d = tonumber(d)
  if not a or not b or not c or not d then return false end
  if a < 0 or 255 < a then return false end
  if b < 0 or 255 < b then return false end
  if c < 0 or 255 < c then return false end
  if d < 0 or 255 < d then return false end

  return true
end

local function is_valid_address(value, only_IPv4)
  if not value or stringy.strip(value) == "" then return false end

  local parts = stringy.split(value, ":")
  if #parts ~= 2 then return false end
  if stringy.strip(parts[1]) == "" then return false end
  if only_IPv4 and not is_valid_IPv4(parts[1]) then return false end
  local port = tonumber(parts[2])
  if not port then return false end
  if not (port > 0 and port <= 65535) then return false end

  return true
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

  -- Check listen addresses
  if config.proxy_listen and not is_valid_address(config.proxy_listen) then
    return false, {proxy_listen = config.proxy_listen.." is not a valid \"host:port\" value"}
  end
  if config.proxy_listen_ssl and not is_valid_address(config.proxy_listen_ssl) then
    return false, {proxy_listen_ssl = config.proxy_listen_ssl.." is not a valid \"host:port\" value"}
  end
  if config.admin_api_listen and not is_valid_address(config.admin_api_listen) then
    return false, {admin_api_listen = config.admin_api_listen.." is not a valid \"host:port\" value"}
  end
  -- Cluster listen addresses must have an IPv4 host (no hostnames)
  if config.cluster_listen and not is_valid_address(config.cluster_listen, true) then
    return false, {cluster_listen = config.cluster_listen.." is not a valid \"ip:port\" value"}
  end
  if config.cluster_listen_rpc and not is_valid_address(config.cluster_listen_rpc, true) then
    return false, {cluster_listen_rpc = config.cluster_listen_rpc.." is not a valid \"ip:port\" value"}
  end
  -- Same for the cluster.advertise value
  if config.cluster and config.cluster.advertise and stringy.strip(config.cluster.advertise) ~= "" and not is_valid_address(config.cluster.advertise, true) then
    return false, {["cluster.advertise"] = config.cluster.advertise.." is not a valid \"ip:port\" value"}
  end

  return true
end

local DEFAULT_CONFIG = {}

function _M.default_config()
  if next(DEFAULT_CONFIG) == nil then
    _M.validate(DEFAULT_CONFIG)
  end

  return DEFAULT_CONFIG
end

function _M.load(config_path)
  local config_contents = IO.read_file(config_path)
  if not config_contents then
    logger:error("No configuration file at: "..config_path)
    os.exit(1)
  end

  local status,config = pcall(yaml.load,config_contents)
  if not status then
    logger:error("Could not parse configuration at: "..config_path)
    os.exit(1)
  end

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
  config.dao_config = config[config.database]
  if config.dns_resolver == "dnsmasq" then
    config.dns_resolver = {
      address = "127.0.0.1:"..config.dns_resolvers_available.dnsmasq.port,
      port = config.dns_resolvers_available.dnsmasq.port,
      dnsmasq = true
    }
  else
    config.dns_resolver = {address = config.dns_resolvers_available.server.address}
  end

  -- Load absolute path for the nginx working directory
  if not stringy.startswith(config.nginx_working_dir, "/") then
    -- It's a relative path, convert it to absolute
    local fs = require "luarocks.fs"
    config.nginx_working_dir = fs.current_dir().."/"..config.nginx_working_dir
  end

  config.plugins = utils.concat(constants.PLUGINS_AVAILABLE, config.custom_plugins)

  return config, config_path
end

function _M.load_default(config_path)
  logger:info("Using configuration: "..config_path)

  return _M.load(config_path)
end

return _M
