#!/usr/bin/env lua

local cutils = require "kong.cli.utils"
local constants = require "kong.constants"
local args = require("lapp")(string.format([[
Usage: kong start [options]

Options:
  -c,--config (default %s) configuration file
]], constants.CLI.GLOBAL_KONG_CONF))

-- Make sure nginx is there and is openresty
local nginx_path = cutils.find_nginx()
if not nginx_path then
  cutils.logger:error_exit("can't find nginx")
end

-- Get configuration from default or given path
local config_path = cutils.get_kong_config_path(args.config)
local config, dao_factory = cutils.load_configuration_and_dao(config_path)

-- Migrate the DB if needed and possible
local keyspace, err = dao_factory:get_migrations()
if err then
  cutils.logger:error_exit(err)
elseif keyspace == nil then
  cutils.logger:log("Database not initialized. Running migrations...")
  local migrations = require("kong.tools.migrations")(dao_factory)
  migrations:migrate(function(migration, err)
    if err then
      cutils.logger:error_exit(err)
    elseif migration then
      cutils.logger:success("Migrated up to: "..cutils.colors.yellow(migration.name))
    end
  end)
end

-- Prepare nginx --prefix dir
local nginx_working_dir = cutils.prepare_nginx_working_dir(config)

-- Build nginx start command
local cmd = string.format("KONG_CONF=%s %s -p %s -c %s -g 'pid %s;'",
                          config_path,
                          nginx_path,
                          nginx_working_dir,
                          constants.CLI.NGINX_CONFIG,
                          constants.CLI.NGINX_PID)

if os.execute(cmd) == 0 then
  cutils.logger:success("Started")
else
  cutils.logger:error_exit("Could not start Kong")
end
