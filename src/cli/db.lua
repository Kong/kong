#!/usr/bin/env lua

local Faker = require "kong.tools.faker"
local Migrations = require "kong.tools.migrations"

local constants = require "kong.constants"
local cutils = require "kong.cli.utils"
local IO = require "kong.tools.io"
local lapp = require("lapp")
local args = lapp(string.format([[
Migrations, seeding of the DB.

Usage: kong db <command> [options]

Commands:
  <command> (string) where <command> is one of:
                       migrations, migrations:up, migrations:down, migrations:reset, seed, drop

Options:
  -c,--config (default %s) configuration file
  -r,--random                              <seed>: flag to also insert random entities
  -n,--number (default 1000)               <seed>: number of random entities to insert if --random
]], constants.CLI.GLOBAL_KONG_CONF))

-- $ kong db
if args.command == "db" then
  lapp.quit("Missing required <command>.")
end

local config_path = cutils.get_kong_config_path(args.config)
local _, dao_factory = IO.load_configuration_and_dao(config_path)
local migrations = Migrations(dao_factory, cutils.get_luarocks_install_dir())

if args.command == "migrations" then

  local migrations, err = dao_factory:get_migrations()
  if err then
    cutils.logger:error_exit(err)
  elseif migrations then
    cutils.logger:log(string.format(
      "Executed migrations for %s on keyspace: %s:\n%s",
      cutils.colors.yellow(dao_factory.type),
      cutils.colors.yellow(dao_factory._properties.keyspace),
      table.concat(migrations, ", ")
    ))
  else
    cutils.logger:log(string.format(
      "No migrations have been run yet for %s on keyspace: %s",
      cutils.colors.yellow(dao_factory.type),
      cutils.colors.yellow(dao_factory._properties.keyspace)
    ))
  end


elseif args.command == "migrations:up" then

  cutils.logger:log(string.format(
    "Migrating %s keyspace: %s",
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

elseif args.command == "migrations:down" then

  cutils.logger:log(string.format(
    "Rolling back %s keyspace: %s",
    cutils.colors.yellow(dao_factory.type),
    cutils.colors.yellow(dao_factory._properties.keyspace)
  ))

  migrations:rollback(function(migration, err)
    if err then
      cutils.logger:error_exit(err)
    elseif migration then
      cutils.logger:success("Rollbacked to: "..cutils.colors.yellow(migration.name))
    else
      cutils.logger:success("No migration to rollback")
    end
  end)

elseif args.command == "migrations:reset" then

  cutils.logger:log(string.format(
    "Reseting %s keyspace: %s",
    cutils.colors.yellow(dao_factory.type),
    cutils.colors.yellow(dao_factory._properties.keyspace))
  )

  migrations:reset(function(migration, err)
    if err then
      cutils.logger:error_exit(err)
    elseif migration then
      cutils.logger:success("Rollbacked: "..cutils.colors.yellow(migration.name))
    else
      cutils.logger:success("Schema reseted")
    end
  end)

elseif args.command == "seed" then

  -- Drop if exists
  local err = dao_factory:drop()
  if err then
    cutils.logger:error_exit(err)
  end

  local err = dao_factory:prepare()
  if err then
    cutils.logger:error(err)
  end

  local faker = Faker(dao_factory)
  faker:seed(args.random and args.number or nil)
  cutils.logger:success("Populated")

elseif args.command == "drop" then

  local err = dao_factory:drop()
  if err then
    cutils.logger:error_exit(err)
  end

  cutils.logger:success("Dropped")

else
  lapp.quit("Invalid command: "..args.command)
end
