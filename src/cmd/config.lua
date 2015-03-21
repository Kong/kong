#!/usr/bin/env lua

local utils = require "kong.tools.utils"
local cutils = require "kong.cmd.utils"
local args = require "lapp" [[
Duplicate an existing configuration for given environment.

Usage: kong config [options]

Options:
  -c,--config (default kong.yml)  configuration file
  -o,--output (default .)         ouput
  -e,--env    (string)            environment name
]]

local CONFIG_FILENAME = string.format("kong%s.yml", args.env ~= "" and "_"..args.env or "")
local config_content = utils.read_file(args.config)

local DEFAULT_ENV_VALUES = {
  TEST = {
    ["send_anonymous_reports: true"] = "send_anonymous_reports: false",
    ["keyspace: kong"] = "keyspace: kong_tests",
    ["lua_package_path ';;'"] = "lua_package_path './src/?.lua;;'",
    ["error_log logs/error.log info"] = "error_log logs/error.log debug",
    ["listen 8000"] = "listen 8100",
    ["listen 8001"] = "listen 8101"
  },
  DEVELOPMENT = {
    ["send_anonymous_reports: true"] = "send_anonymous_reports: false",
    ["keyspace: kong"] = "keyspace: kong_development",
    ["lua_package_path ';;'"] = "lua_package_path './src/?.lua;;'",
    ["error_log logs/error.log info"] = "error_log logs/error.log debug",
    ["lua_code_cache on"] = "lua_code_cache off",
    ["daemon on"] = "daemon off"
  }
}

-- Create a new default kong config for given environment
if DEFAULT_ENV_VALUES[args.env:upper()] then
  -- If we know the environment we can override some of the variables
  for k, v in pairs(DEFAULT_ENV_VALUES[args.env:upper()]) do
    config_content = config_content:gsub(k, v)
  end
end

utils.write_to_file(cutils.path:join(args.output, CONFIG_FILENAME), config_content)
