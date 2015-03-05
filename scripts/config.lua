#!/usr/bin/env lua

local cli = require "cliargs"
local path = require("path").new("/")
local yaml = require "yaml"
local utils = require "kong.tools.utils"

cli:set_name("config.lua")
cli:add_argument("COMMAND", "{create|nginx}")
cli:add_option("-c, --config=CONFIG", "config file", "kong.yml")
cli:add_option("-o, --output=OUTPUT", "output file (for create)", ".")
cli:add_option("-k, --kong=KONG_HOME", "KONG_HOME (where Kong is installed)", ".")
cli:add_option("-e, --env=ENV", "environment name (for create)", "")

local args = cli:parse(arg)
if not args then
  os.exit(1)
end

local CONFIG_FILENAME = string.format("kong%s.yml", args.env ~= "" and "_"..args.env or "")
local config_content = utils.read_file(args.config)
local config = yaml.load(config_content)

if args.COMMAND == "create" then

  local DEFAULT_ENV_VALUES = {
    TEST = {
      ["keyspace: kong"] = "keyspace: kong_tests",
      ["lua_package_path \";;\""] = "lua_package_path \""..args.kong.."/src/?.lua;;\"",
      ["error_log logs/error.log info"] = "error_log logs/error.log debug"
    },
    DEVELOPMENT = {
      ["keyspace: kong"] = "keyspace: kong_development",
      ["lua_package_path \";;\""] = "lua_package_path \""..args.kong.."/src/?.lua;;\"",
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

  utils.write_to_file(path:join(args.output, CONFIG_FILENAME), config_content)

elseif args.COMMAND == "nginx" then

  -- Write nginx config file to given path
  utils.write_to_file(path:join(args.output, "nginx.conf"), config.nginx)

else
  print("Invalid command: "..args.COMMAND)
end
