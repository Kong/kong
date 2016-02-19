#!/usr/bin/env luajit

local constants = require "kong.constants"
local config_loader = require "kong.tools.config_loader"
local logger = require "kong.cli.utils.logger"
local services = require "kong.cli.utils.services"

local args = require("lapp")(string.format([[
Start Kong with given configuration. Kong will run in the configured 'nginx_working_dir' directory.

Usage: kong start [options]

Options:
  -c,--config (default %s) path to configuration file
]], constants.CLI.GLOBAL_KONG_CONF))

logger:info("Kong "..constants.VERSION)

local configuration, configuration_path = config_loader.load_default(args.config)

local status = services.check_status(configuration, configuration_path)
if status == services.STATUSES.SOME_RUNNING then
  logger:error("Some services required by Kong are already running. Please execute \"kong restart\"!")
  os.exit(1)
elseif status == services.STATUSES.ALL_RUNNING then
  logger:error("Kong is currently running")
  os.exit(1)
end

if not configuration.daemon then
  local terminate_daemon = function()
    services.stop_all(configuration, configuration_path)
    logger:success("Stopped")
    os.exit(0)
  end
  local signal = require "posix.signal"
  signal.signal(signal.SIGTERM, function() terminate_daemon() end)
  signal.signal(signal.SIGINT, function() terminate_daemon() end)
end

local ok, err = services.start_all(configuration, configuration_path)
if not ok then
  services.stop_all(configuration, configuration_path)
  logger:error(err)
  logger:error("Could not start Kong")
  os.exit(1)
end

logger:success("Started"..((configuration.daemon) and "" or " in foreground mode"))

if not configuration.daemon then
  while(true) do
    io.read()
  end
end

