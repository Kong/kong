#!/usr/bin/env luajit

local Migrations = require "kong.tools.migrations"
local constants = require "kong.constants"
local logger = require "kong.cli.utils.logger"
local utils = require "kong.tools.utils"
local input = require "kong.cli.utils.input"
local config_loader = require "kong.tools.config_loader"
local dao = require "kong.tools.dao_loader"
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
local dao_factory = dao.load(configuration)
local migrations = Migrations(dao_factory, configuration)

local kind = args.type
if kind ~= "all" and kind ~= "core" then
  -- Assuming we are trying to run migrations for a plugin
  if not utils.table_contains(configuration.plugins, kind) then
    logger:error("No \""..kind.."\" plugin enabled in the configuration.")
    os.exit(1)
  end
end

if args.command == "list" then

  local migrations, err = dao_factory.migrations:get_migrations()
  if err then
    logger:error(err)
    os.exit(1)
  elseif migrations then
    logger:info(string.format(
      "Executed migrations for keyspace %s (%s):",
      logger.colors.yellow(dao_factory.properties.keyspace),
      dao_factory.type
    ))

    for _, row in ipairs(migrations) do
      logger:info(string.format("%s: %s",
        logger.colors.yellow(row.id),
        table.concat(row.migrations, ", ")
      ))
    end
  else
    logger:info(string.format(
      "No migrations have been run yet for %s on keyspace: %s",
      logger.colors.yellow(dao_factory.type),
      logger.colors.yellow(dao_factory.properties.keyspace)
    ))
  end

elseif args.command == "up" then

  local function before(identifier)
    logger:info(string.format(
      "Migrating %s on keyspace \"%s\" (%s)",
      logger.colors.yellow(identifier),
      logger.colors.yellow(dao_factory.properties.keyspace),
      dao_factory.type
    ))
  end

  local function on_each_success(identifier, migration)
    logger:info(string.format(
      "%s migrated up to: %s",
      identifier,
      logger.colors.yellow(migration.name)
    ))
  end

  if kind == "all" then
    local err = migrations:run_all_migrations(before, on_each_success)
    if err then
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

elseif args.command == "down" then

  if kind == "all" then
    logger:error("You must specify 'core' or a plugin name for this command.")
    os.exit(1)
  end

  local function before(identifier)
    logger:info(string.format(
      "Rollbacking %s in keyspace \"%s\" (%s)",
      logger.colors.yellow(identifier),
      logger.colors.yellow(dao_factory.properties.keyspace),
      dao_factory.type
    ))
  end

  local function on_success(identifier, migration)
    if migration then
      logger:success("\""..identifier.."\" rollbacked: "..logger.colors.yellow(migration.name))
    else
      logger:success("No migration to rollback")
    end
  end

  local err = migrations:run_rollback(kind, before, on_success)
  if err then
    logger:error(err)
    os.exit(1)
  end

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