#!/usr/bin/env lua

local Faker = require "kong.tools.faker"
local Migrations = require "kong.tools.migrations"

local cutils = require "kong.cmd.utils"
local utils = require "kong.tools.utils"
local lapp = require("lapp")
local args = lapp(string.format([[
Usage: kong db <command> [options]

Commands:
  <command> (string) where <command> is one of:
                       migrate:up, migrate:down, migrate:reset, seed, drop

Options:
  -c,--config (default %s) configuration file
  -r,--random                              <seed>: flag to also insert random entities
  -n,--number (default 1000)               <seed>: number of random entities to insert if --random
]], cutils.CONSTANTS.GLOBAL_KONG_CONF))

-- $ kong db
if args.command == "db" then
  lapp.quit("Missing command.")
end

local config_path, config = cutils.get_kong_config(args.config)
-- TODO: move to config validation
local status, res = pcall(require, "kong.dao."..config.database..".factory")
if not status then
  cutils.logger:error("Wrong config")
  os.exit(1)
end

local dao_factory = res(config.databases_available[config.database].properties)
local migrations = Migrations(dao_factory)

if args.command == "migrate:up" then

  cutils.logger:log(string.format(
    cutils.colors("Migrating %{yellow}%s%{reset} keyspace: %{yellow}%s%{reset}"),
    dao_factory.type,
    dao_factory._properties.keyspace)
  )

  migrations:migrate(function(migration, err)
    if err then
      cutils.logger:error(err)
      os.exit(1)
    elseif migration then
      cutils.logger:success("Migrated up to: "..cutils.colors("%{yellow}"..migration.name.."%{reset}"))
    else
      cutils.logger:success("Schema already up to date")
    end
  end)

elseif args.command == "migrate:down" then

  cutils.logger:log(string.format(
    cutils.colors("Rolling back %{yellow}%s%{reset} keyspace: %{yellow}%s%{reset}"),
    dao_factory.type,
    dao_factory._properties.keyspace)
  )

  migrations:rollback(function(migration, err)
    if err then
      cutils.logger:error(err)
      os.exit(1)
    elseif migration then
      cutils.logger:success("Rollbacked to: "..cutils.colors("%{yellow}"..migration.name.."%{reset}"))
    else
      cutils.logger:success("No migration to rollback")
    end
  end)

elseif args.command == "migrate:reset" then

  cutils.logger:log(string.format(
    cutils.colors("Reseting %{yellow}%s%{reset} keyspace: %{yellow}%s%{reset}"),
    dao_factory.type,
    dao_factory._properties.keyspace)
  )

  migrations:reset(function(migration, err)
    if err then
      cutils.logger:error(err)
      os.exit(1)
    elseif migration then
      cutils.logger:success("Rollbacked: "..cutils.colors("%{yellow}"..migration.name.."%{reset}"))
    else
      cutils.logger:success("Schema reseted")
    end
  end)

elseif args.command == "seed" then

  -- Drop if exists
  local err = dao_factory:drop()
  if err then
    cutils.logger:error(err)
    os.exit(1)
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
    cutils.logger:error(err)
    os.exit(1)
  end

  cutils.logger:success("Dropped")

else
  lapp.quit("Invalid command: "..args.command)
end
