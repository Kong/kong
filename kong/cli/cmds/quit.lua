#!/usr/bin/env luajit

local constants = require "kong.constants"
local logger = require "kong.cli.utils.logger"
local config_loader = require "kong.tools.config_loader"
local Nginx = require "kong.cli.services.nginx"
local services = require "kong.cli.utils.services"
local args = require("lapp")(string.format([[
Graceful shutdown. Stop the Kong instance running in the configured 'nginx_working_dir' directory.

Usage: kong stop [options]

Options:
  -c,--config (default %s) path to configuration file
]], constants.CLI.GLOBAL_KONG_CONF))

local configuration, configuration_path = config_loader.load_default(args.config)

local nginx = Nginx(configuration, configuration_path)

if not nginx:is_running() then
  logger:error("Kong is not running")
  os.exit(1)
end

nginx:quit()
while(nginx:is_running()) do
  -- Wait until it quits
end

services.stop_all(configuration, configuration_path)
logger:success("Stopped")