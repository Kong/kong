#!/usr/bin/env luajit

local Migrations = require "kong.tools.migrations"
local constants = require "kong.constants"
local cutils = require "kong.cli.utils"
local utils = require "kong.tools.utils"
local input = require "kong.cli.utils.input"
local config = require "kong.tools.config_loader"
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

local config_path = cutils.get_kong_config_path(args.config)
local configuration = config.load(config_path)
local dao_factory = dao.load(configuration)
local migrations = Migrations(dao_factory, configuration)

local kind = args.type
if kind ~= "all" and kind ~= "core" then
  -- Assuming we are trying to run migrations for a plugin
  if not utils.table_contains(configuration.plugins_available, kind) then
    cutils.logger:error_exit("No \""..kind.."\" plugin enabled in the configuration.")
  end
end

if args.command == "list" then

  local migrations, err = dao_factory.migrations:get_migrations()
  if err then
    cutils.logger:error_exit(err)
  elseif migrations then
    cutils.logger:info(string.format(
      "Executed migrations for keyspace %s (%s):",
      cutils.colors.yellow(dao_factory.properties.keyspace),
      dao_factory.type
    ))

    for _, row in ipairs(migrations) do
      cutils.logger:info(string.format("%s: %s",
        cutils.colors.yellow(row.id),
        table.concat(row.migrations, ", ")
      ))
    end
  else
    cutils.logger:info(string.format(
      "No migrations have been run yet for %s on keyspace: %s",
      cutils.colors.yellow(dao_factory.type),
      cutils.colors.yellow(dao_factory.properties.keyspace)
    ))
  end

elseif args.command == "up" then

  local function before(identifier)
    cutils.logger:info(string.format(
      "Migrating %s on keyspace \"%s\" (%s)",
      cutils.colors.yellow(identifier),
      cutils.colors.yellow(dao_factory.properties.keyspace),
      dao_factory.type
    ))
  end

  local function on_each_success(identifier, migration)
    cutils.logger:info(string.format(
      "%s migrated up to: %s",
      identifier,
      cutils.colors.yellow(migration.name)
    ))
  end

  if kind == "all" then
    local err = migrations:run_all_migrations(before, on_each_success)
    if err then
      cutils.logger:error_exit(err)
    end
  else
    local err = migrations:run_migrations(kind, before, on_each_success)
    if err then
      cutils.logger:error_exit(err)
    end
  end

  cutils.logger:success("Schema up to date")

elseif args.command == "down" then

  if kind == "all" then
    cutils.logger:error_exit("You must specify 'core' or a plugin name for this command.")
  end

  local function before(identifier)
    cutils.logger:info(string.format(
      "Rollbacking %s in keyspace \"%s\" (%s)",
      cutils.colors.yellow(identifier),
      cutils.colors.yellow(dao_factory.properties.keyspace),
      dao_factory.type
    ))
  end

  local function on_success(identifier, migration)
    if migration then
      cutils.logger:success("\""..identifier.."\" rollbacked: "..cutils.colors.yellow(migration.name))
    else
      cutils.logger:success("No migration to rollback")
    end
  end

  local err = migrations:run_rollback(kind, before, on_success)
  if err then
    cutils.logger:error_exit(err)
  end

elseif args.command == "reset" then

  local keyspace = dao_factory.properties.keyspace

  cutils.logger:info(string.format(
    "Resetting \"%s\" keyspace (%s)",
    cutils.colors.yellow(keyspace),
    dao_factory.type
  ))

  if input.confirm("Are you sure? You will lose all of your data, this operation is irreversible.") then
    local _, err = dao_factory.migrations:drop_keyspace(keyspace)
    if err then
      cutils.logger:error_exit(err)
    else
      cutils.logger:success("Keyspace successfully reset")
    end
  end
else
  lapp.quit("Invalid command: "..args.command)
end
