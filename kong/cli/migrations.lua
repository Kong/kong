#!/usr/bin/env lua

local Migrations = require "kong.tools.migrations"
local constants = require "kong.constants"
local cutils = require "kong.cli.utils"
local utils = require "kong.tools.utils"
local input = require "kong.cli.utils.input"
local IO = require "kong.tools.io"
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
local configuration, dao_factory = IO.load_configuration_and_dao(config_path)
local migrations = Migrations(dao_factory)

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
      cutils.colors.yellow(dao_factory._properties.keyspace),
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
      cutils.colors.yellow(dao_factory._properties.keyspace)
    ))
  end

elseif args.command == "up" then

  local function migrate(identifier)
    cutils.logger:info(string.format(
      "Migrating %s on keyspace \"%s\" (%s)",
      cutils.colors.yellow(identifier),
      cutils.colors.yellow(dao_factory._properties.keyspace),
      dao_factory.type
    ))

    local err = migrations:migrate(identifier, function(identifier, migration)
      if migration then
        cutils.logger:info(string.format(
          "%s migrated up to: %s",
          identifier,
          cutils.colors.yellow(migration.name)
        ))
      end
    end)
    if err then
      cutils.logger:error_exit(err)
    end
  end

  if kind == "all" then
    migrate("core")
    for _, plugin_name in ipairs(configuration.plugins_available) do
      local has_migrations = utils.load_module_if_exists("kong.plugins."..plugin_name..".migrations."..dao_factory.type)
      if has_migrations then
        migrate(plugin_name)
      end
    end
  else
    migrate(kind)
  end

  cutils.logger:success("Schema up to date")

elseif args.command == "down" then

  if kind == "all" then
    cutils.logger:error_exit("You must specify 'core' or a plugin name for this command.")
  end

  cutils.logger:info(string.format(
    "Rollbacking %s in keyspace \"%s\" (%s)",
    cutils.colors.yellow(kind),
    cutils.colors.yellow(dao_factory._properties.keyspace),
    dao_factory.type
  ))

  local rollbacked, err = migrations:rollback(kind)
  if err then
    cutils.logger:error_exit(err)
  elseif rollbacked then
    cutils.logger:success("\""..kind.."\" rollbacked: "..cutils.colors.yellow(rollbacked.name))
  else
    cutils.logger:success("No migration to rollback")
  end

elseif args.command == "reset" then

  local keyspace = dao_factory._properties.keyspace

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
