local conf_loader = require "kong.conf_loader"
local DAOFactory = require "kong.dao.factory"
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
  local dao = assert(DAOFactory.new(conf))

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
    if confirm("Are you sure? This operation is irreversible.") then
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
]]

return {
  lapp = lapp,
  execute = execute,
  sub_commands = {up = true, list = true, reset = true}
}
