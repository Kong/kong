#!/usr/bin/env luajit

local constants = require "kong.constants"
local logger = require "kong.cli.utils.logger"
local input = require "kong.cli.utils.input"
local config_loader = require "kong.tools.config_loader"
local dao_loader = require "kong.tools.dao_loader"
local lapp = require "lapp"
local args = lapp(string.format([[
Kong datastore migrations.

Usage: kong migrations <command> [options]

Commands:
  <command> (string) where <command> is one of:
                       list, up, reset

Options:
  -c,--config (default %s) path to configuration file.
]], constants.CLI.GLOBAL_KONG_CONF))

-- $ kong migrations
if args.command == "migrations" then
  lapp.quit "Missing required <command>."
end

local configuration = config_loader.load_default(args.config)
local factory = dao_loader.load(configuration)
local db_details = factory:infos()
db_details.name = logger.colors.yellow(db_details.name)

if args.command == "list" then

  local migrations, err = factory:current_migrations()
  if err then
    logger:error(err)
    os.exit(1)
  elseif next(migrations) then
    logger:info(string.format(
      "Executed migrations for %s %s:",
      db_details.desc, db_details.name
    ))

    for id, row in pairs(migrations) do
      logger:info(string.format("%s: %s",
        logger.colors.yellow(id),
        table.concat(row, ", ")
      ))
    end
  else
    logger:info(string.format(
      "No migrations have been run yet for %s %s",
      db_details.desc, db_details.name
    ))
  end

elseif args.command == "up" then

  local function on_migrate(identifier)
    logger:info(string.format(
      "Migrating %s for %s %s",
      logger.colors.yellow(identifier),
      db_details.desc, db_details.name
    ))
  end

  local function on_success(identifier, migration_name)
    logger:info(string.format(
      "%s migrated up to: %s",
      identifier,
      migration_name
    ))
  end

  local ok, err = factory:run_migrations(on_migrate, on_success)
  if not ok then
    logger:error(err)
    os.exit(1)
  end

  logger:success "Schema up to date"

elseif args.command == "reset" then

  logger:info(string.format(
    "Resetting schema for %s %s",
    db_details.desc, db_details.name
  ))

  if input.confirm("Are you sure? You will lose all of your data, this operation is irreversible.") then
    local _, err = factory:drop_schema()
    if err then
      logger:error(err)
      os.exit(1)
    else
      logger:success "Schema successfully reset"
    end
  end
else
  lapp.quit("Invalid command: "..args.command)
end
