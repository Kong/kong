#!/usr/bin/env luajit

local constants = require "kong.constants"
local config_loader = require "kong.tools.config_loader"
local services = require "kong.cli.utils.services"

local args = require("lapp")(string.format([[
Restart the Kong instance running in the configured 'nginx_working_dir'.

Kong will be shutdown before restarting. For a zero-downtime reload
of your configuration, look at 'kong reload'.

Usage: kong restart [options]

Options:
  -c,--config (default %s) path to configuration file
]], constants.CLI.GLOBAL_KONG_CONF))

local configuration, configuration_path = config_loader.load_default(args.config)

services.stop_all(configuration, configuration_path)

require("kong.cli.cmds.start")