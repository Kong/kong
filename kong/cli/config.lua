#!/usr/bin/env lua

local constants = require "kong.constants"
local cutils = require "kong.cli.utils"
local IO = require "kong.tools.io"
local args = require("lapp")(string.format([[
For development purposes only.

Duplicate an existing configuration for given environment.

Usage: kong config [options]

Options:
  -c,--config (default %s) path to configuration file
  -o,--output (default .)                  ouput
  -e,--env    (string)                     environment name
]], constants.CLI.GLOBAL_KONG_CONF))

local CONFIG_FILENAME = string.format("kong%s.yml", args.env ~= "" and "_"..args.env or "")

local config_path = cutils.get_kong_config_path(args.config)
local config_content = IO.read_file(config_path)

local DEFAULT_ENV_VALUES = {
  TEST = {
    ["nginx_working_dir: /usr/local/kong/"] = "nginx_working_dir: nginx_tmp",
    ["send_anonymous_reports: true"] = "send_anonymous_reports: false",
    ["keyspace: kong"] = "keyspace: kong_tests",
    ["lua_package_path ';;'"] = "lua_package_path './kong/?.lua;;'",
    ["error_log logs/error.log info"] = "error_log logs/error.log debug",
    ["proxy_port: 8000"] = "proxy_port: 8100",
    ["admin_api_port: 8001"] = "admin_api_port: 8101"
  },
  DEVELOPMENT = {
    ["nginx_working_dir: /usr/local/kong/"] = "nginx_working_dir: nginx_tmp",
    ["send_anonymous_reports: true"] = "send_anonymous_reports: false",
    ["keyspace: kong"] = "keyspace: kong_development",
    ["lua_package_path ';;'"] = "lua_package_path './kong/?.lua;;'",
    ["error_log logs/error.log info"] = "error_log logs/error.log debug",
    ["lua_code_cache on"] = "lua_code_cache off"
  }
}

-- Create a new default kong config for given environment
if DEFAULT_ENV_VALUES[args.env:upper()] then
  -- If we know the environment we can override some of the variables
  for k, v in pairs(DEFAULT_ENV_VALUES[args.env:upper()]) do
    config_content = config_content:gsub(k, v)
  end
end

local ok, err = IO.write_to_file(IO.path:join(args.output, CONFIG_FILENAME), config_content)
if not ok then
  error(err)
end
