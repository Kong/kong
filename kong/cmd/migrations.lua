---[==[
local DB = require "kong.db"
local log = require "kong.cmd.utils.log"
local conf_loader = require "kong.conf_loader"
local migrations_utils = require "kong.cmd.utils.migrations"


-- TODO: argument so migrations can take more than 60s without other nodes
-- timing out
local CASSANDRA_TIMEOUT = 60000


local lapp = [[
Usage: kong migrations COMMAND [OPTIONS]

Manage Kong's database migrations.

The available commands are:
  list
  check
  bootstrap
  up
  finish
  reset

Options:
  -c,--conf        (optional string) configuration file
]]


local function execute(args)
  local conf = assert(conf_loader(args.conf))
  conf.cassandra_timeout = CASSANDRA_TIMEOUT -- TODO: separate read_timeout from connect_timeout

  local db = DB.new(conf)
  assert(db:init_connector())

  local schema_state = assert(db:schema_state())

  if args.command == "list" then
    log("executed migrations:\n%s", schema_state.executed_migrations)

  elseif args.command == "check" then
    migrations_utils.print_state(schema_state)

  elseif args.command == "bootstrap" then
    migrations_utils.bootstrap(schema_state, db)

  elseif args.command == "reset" then
    migrations_utils.reset(db)

  elseif args.command == "up" then
    migrations_utils.up(schema_state, db)

  elseif args.command == "finish" then
    migrations_utils.finish(schema_state, db)

    -- TODO: list
    -- TODO: get rid of 'bootstrap' -> automatic migrations

  else
    error("NYI")
  end
end


return {
  lapp = lapp,
  execute = execute,
  sub_commands = {
    list = true,
    bootstrap = true,
    check = true,
    reset = true,
    up = true,
    finish = true,
  }
}
--]==]


--[==[
local conf_loader = require "kong.conf_loader"
local DAOFactory = require "kong.dao.factory"
local DB = require "kong.db"
local log = require "kong.cmd.utils.log"
local concat = table.concat

local ANSWERS = {
  y = true,
  Y = true,
  yes = true,
  YES = true,
  n = false,
  N = false,
  no = false,
  NO = false
}

local function confirm(q)
  local max = 3
  while max > 0 do
    io.write("> " .. q .. " [Y/n] ")
    local a = io.read("*l")
    if ANSWERS[a] ~= nil then
      return ANSWERS[a]
    end
    max = max - 1
  end
end

local function execute(args)
  local conf = assert(conf_loader(args.conf))
  local db = assert(DB.new(conf))
  assert(db:init_connector())
  local dao = assert(DAOFactory.new(conf, db))

  if args.command == "up" then
    assert(dao:run_migrations())
  elseif args.command == "list" then
    local migrations = assert(dao:current_migrations())
    local db_infos = dao:infos()
    if next(migrations) then
      log("Executed migrations for %s '%s':",
          db_infos.desc, db_infos.name)
      for id, row in pairs(migrations) do
        log("%s: %s", id, concat(row, ", "))
      end
    else
      log("No migrations have been run yet for %s '%s'",
          db_infos.desc, db_infos.name)
    end
  elseif args.command == "reset" then
    if args.yes
      or confirm("Are you sure? This operation is irreversible.")
    then
      dao:drop_schema()
      log("Schema successfully reset")
    else
      log("Canceled")
    end
  end
end

local lapp = [[
Usage: kong migrations COMMAND [OPTIONS]

Manage Kong's database migrations.

The available commands are:
 list   List migrations currently executed.
 up     Execute all missing migrations up to the latest available.
 reset  Reset the configured database (irreversible).

Options:
 -c,--conf        (optional string) configuration file
 -y,--yes         assume "yes" to prompts and run non-interactively
]]

return {
  lapp = lapp,
  execute = execute,
  sub_commands = {up = true, list = true, reset = true}
}
--]==]
