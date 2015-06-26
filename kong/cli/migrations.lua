#!/usr/bin/env lua

local Migrations = require "kong.tools.migrations"
local constants = require "kong.constants"
local cutils = require "kong.cli.utils"
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
  -c,--config (default %s) path to configuration file
]], constants.CLI.GLOBAL_KONG_CONF))

-- $ kong migrations
if args.command == "migrations" then
  lapp.quit("Missing required <command>.")
end

local config_path = cutils.get_kong_config_path(args.config)
local _, dao_factory = IO.load_configuration_and_dao(config_path)
local migrations = Migrations(dao_factory, cutils.get_luarocks_install_dir())

if args.command == "list" then

  local migrations, err = dao_factory.migrations:get_migrations()
  if err then
    cutils.logger:error_exit(err)
  elseif migrations then
    cutils.logger:info(string.format(
      "Executed migrations for %s on keyspace %s:\n%s",
      cutils.colors.yellow(dao_factory.type),
      cutils.colors.yellow(dao_factory._properties.keyspace),
      table.concat(migrations, ", ")
    ))
  else
    cutils.logger:info(string.format(
      "No migrations have been run yet for %s on keyspace: %s",
      cutils.colors.yellow(dao_factory.type),
      cutils.colors.yellow(dao_factory._properties.keyspace)
    ))
  end

elseif args.command == "up" then

  cutils.logger:info(string.format(
    "Migrating %s keyspace \"%s\"",
    cutils.colors.yellow(dao_factory.type),
    cutils.colors.yellow(dao_factory._properties.keyspace))
  )

  migrations:migrate(function(migration, err)
    if err then
      cutils.logger:error_exit(err)
    elseif migration then
      cutils.logger:success("Migrated up to: "..cutils.colors.yellow(migration.name))
    else
      cutils.logger:success("Schema already up to date")
    end
  end)

elseif args.command == "down" then

  cutils.logger:info(string.format(
    "Rollbacking %s keyspace \"%s\"",
    cutils.colors.yellow(dao_factory.type),
    cutils.colors.yellow(dao_factory._properties.keyspace)
  ))

  migrations:rollback(function(migration, err)
    if err then
      cutils.logger:error_exit(err)
    elseif migration then
      cutils.logger:success("Rollbacked: "..cutils.colors.yellow(migration.name))
    else
      cutils.logger:success("No migration to rollback")
    end
  end)

elseif args.command == "reset" then

  local keyspace = dao_factory._properties.keyspace

  cutils.logger:info(string.format(
    "Resetting %s keyspace \"%s\"",
    cutils.colors.yellow(dao_factory.type),
    cutils.colors.yellow(keyspace)
  ))

  if input.confirm("Are you sure? You will lose all of your data, this operation is irreversible.") then
    local res, err = dao_factory.migrations:drop_keyspace(keyspace)
    if err then
      cutils.logger:error_exit(err)
    else
      cutils.logger:success("Keyspace successfully reset")
    end
  end
else
  lapp.quit("Invalid command: "..args.command)
end
