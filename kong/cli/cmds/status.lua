#!/usr/bin/env luajit

local constants = require "kong.constants"
local logger = require "kong.cli.utils.logger"
local services = require "kong.cli.utils.services"
local config_loader = require "kong.tools.config_loader"
local args = require("lapp")(string.format([[
Checks the status of Kong and its services. Returns an error if the services are not properly running.

Usage: kong status [options]

Options:
  -c,--config (default %s) path to configuration file
]], constants.CLI.GLOBAL_KONG_CONF))

local configuration, configuration_path = config_loader.load_default(args.config)

local status = services.check_status(configuration, configuration_path)
if status == services.STATUSES.ALL_RUNNING then
  logger:info("Kong is running")
  os.exit(0)
elseif status == services.STATUSES.SOME_RUNNING then
  logger:error("Some services required by Kong are not running. Please execute \"kong restart\"!")
  os.exit(1)
else
  logger:error("Kong is not running")
  os.exit(1)
end