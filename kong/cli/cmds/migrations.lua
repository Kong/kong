#!/usr/bin/env luajit

local constants = require "kong.constants"
local logger = require "kong.cli.utils.logger"
local utils = require "kong.tools.utils"
local input = require "kong.cli.utils.input"
local config_loader = require "kong.tools.config_loader"
local dao_loader = require "kong.tools.dao_loader"
local lapp = require "lapp"
local args = lapp(string.format([[
Kong datastore migrations.

Usage: kong migrations <command> [options]

Commands:
  <command> (string) where <command> is one of:
                       list, up, down, reset

Options:
  -c,--config (default %s) path to configuration file.
  -t,--type (default all)  when 'up' or 'down', specify 'core' or 'plugin_name' to only run
                           specific migrations.
]], constants.CLI.GLOBAL_KONG_CONF))

-- $ kong migrations
if args.command == "migrations" then
  lapp.quit("Missing required <command>.")
end

local configuration = config_loader.load_default(args.config)
local factory = dao_loader.load(configuration)

local kind = args.type
if kind ~= "all" and kind ~= "core" then
  -- Assuming we are trying to run migrations for a plugin
  if not utils.table_contains(configuration.plugins, kind) then
    logger:error("No \""..kind.."\" plugin enabled in the configuration.")
    os.exit(1)
  end
end

if args.command == "list" then

  local migrations, err = factory:current_migrations()
  if err then
    logger:error(err)
    os.exit(1)
  elseif migrations then
    logger:info(string.format(
      "Executed migrations (%s):",
      factory.db_type
    ))

    for _, row in ipairs(migrations) do
      logger:info(string.format("%s: %s",
        logger.colors.yellow(row.id),
        table.concat(row.migrations, ", ")
      ))
    end
  else
    logger:info(string.format(
      "No migrations have been run yet for %s",
      logger.colors.yellow(factory.db_type)
    ))
  end

elseif args.command == "up" then

  local function on_migrate(identifier)
    logger:info(string.format(
      "Migrating %s (%s)",
      logger.colors.yellow(identifier),
      factory.db_type
    ))
  end

  local function on_success(identifier, migration_name)
    logger:info(string.format(
      "%s migrated up to: %s",
      identifier,
      logger.colors.yellow(migration_name)
    ))
  end

  if kind == "all" then
    local ok, err = factory:run_migrations(on_migrate, on_success)
    if not ok then
      logger:error(err)
      os.exit(1)
    end
  else
    local err = migrations:run_migrations(kind, before, on_each_success)
    if err then
      logger:error(err)
      os.exit(1)
    end
  end

  logger:success("Schema up to date")

elseif args.command == "reset" then

  local keyspace = dao_factory.properties.keyspace

  logger:info(string.format(
    "Resetting \"%s\" keyspace (%s)",
    logger.colors.yellow(keyspace),
    dao_factory.type
  ))

  if input.confirm("Are you sure? You will lose all of your data, this operation is irreversible.") then
    local _, err = dao_factory.migrations:drop_keyspace(keyspace)
    if err then
      logger:error(err)
      os.exit(1)
    else
      logger:success("Keyspace successfully reset")
    end
  end
else
  lapp.quit("Invalid command: "..args.command)
end
