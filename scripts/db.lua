#!/usr/bin/env lua

local cli = require "cliargs"
local utils = require "kong.tools.utils"
local Faker = require "kong.tools.faker"
local Migrations = require "kong.tools.migrations"

cli:set_name("db.lua")
cli:add_argument("COMMAND", "{create|migrate|rollback|reset|seed|drop}")
cli:add_option("-c, --config=CONFIG", "configuration file", "kong.yml")
cli:add_option("-n, --name=NAME", "If <create>, sets a name to the migration", "new_migration")
cli:add_option("-r, --random=RANDOM_AMOUNT", "If seeding, specify number of random entities to add", "")
cli:add_flag("-s, --silent", "No output")

local args = cli:parse(arg)
if not args then
  os.exit(1)
end

local logger = utils.logger:new(args.silent)
local configuration, dao = utils.load_configuration_and_dao(args.config)

local migrations = Migrations(dao)

if args.COMMAND == "create" then

  Migrations.create(configuration, args.name, function(interface, file_path, file_name)
    os.execute("mkdir -p "..file_path)

    local file = file_path.."/"..file_name..".lua"
    utils.write_to_file(file, interface)
    logger:success("New migration: "..file)
  end)

elseif args.COMMAND == "migrate" then

  logger:log("Migrating "..utils.yellow(dao.type).." keyspace: "..utils.yellow(dao._properties.keyspace))

  migrations:migrate(function(migration, err)
    if err then
      logger:error(err)
    elseif migration then
      logger:success("Migrated up to: "..utils.yellow(migration.name))
    else
      logger:success("Schema already up to date")
    end
  end)

elseif args.COMMAND == "rollback" then

  logger:log("Rolling back "..utils.yellow(dao.type).." keyspace: "..utils.yellow(dao._properties.keyspace))

  migrations:rollback(function(migration, err)
    if err then
      logger:error(err)
    elseif migration then
      logger:success("Rollbacked to: "..utils.yellow(migration.name))
    else
      logger:success("No migration to rollback")
    end
  end)

elseif args.COMMAND == "reset" then

  logger:log("Reseting "..utils.yellow(dao.type).." keyspace: "..utils.yellow(dao._properties.keyspace))

  migrations:reset(function(migration, err)
    if err then
      logger:error(err)
    elseif migration then
      logger:success("Rollbacked: "..utils.yellow(migration.name))
    else
      logger:success("Schema reseted")
    end
  end)

elseif args.COMMAND == "seed" then

  local err

  -- Drop if exists
  err = dao:drop()
  if err then
    logger:error(err)
  end

  err = dao:prepare()
  if err then
    logger:error(err)
  end

  local faker = Faker(dao)
  faker:seed(args.random ~= "" and args.random or nil)
  logger:success("Populated")

elseif args.COMMAND == "drop" then

  dao:drop()
  logger:success("Dropped")

else
  print("Invalid command: "..args.COMMAND)
end
