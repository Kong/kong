#!/usr/bin/env luajit

local constants = require "kong.constants"
local logger = require "kong.cli.utils.logger"
local services = require "kong.cli.utils.services"
local config_loader = require "kong.tools.config_loader"
local args = require("lapp")(string.format([[
Fast shutdown. Stop the Kong instance running in the configured 'nginx_working_dir' directory.

Usage: kong stop [options]

Options:
  -c,--config (default %s) path to configuration file
]], constants.CLI.GLOBAL_KONG_CONF))

local configuration, configuration_path = config_loader.load_default(args.config)

local status = services.check_status(configuration, configuration_path)
if status == services.STATUSES.NOT_RUNNING then
  logger:error("Kong is not running")
  os.exit(1)
end

services.stop_all(configuration, configuration_path)

logger:success("Stopped")