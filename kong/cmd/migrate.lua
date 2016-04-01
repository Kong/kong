local conf_loader = require "kong.conf_loader"
local DAOFactory = require "kong.dao.factory"
local concat = table.concat
local fmt = string.format

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
    io.write(q.." [Y/n] ")
    local a = io.read("*l")
    if ANSWERS[a] ~= nil then
      return ANSWERS[a]
    end
    max = max - 1
  end
end

local function on_migrate(identifier, db_infos)
  print(fmt("Migrating %s for %s %s",
    identifier, db_infos.desc, db_infos.name
  ))
end

local function on_success(identifier, migration_name, db_infos)
  print(fmt("%s migrated up to: %s",
    identifier, migration_name
  ))
end

local function execute(args)
  local conf = assert(conf_loader(args.conf))
  local dao = DAOFactory(conf, conf.plugins)

  if args.command == "up" then
    assert(dao:run_migrations(on_migrate, on_success))
    print("Migrated")
  elseif args.command == "list" then
    local migrations = assert(dao:current_migrations())
    local db_infos = dao:infos()
    if next(migrations) then
      print(fmt("Executed migrations for %s '%s':",
        db_infos.desc, db_infos.name))
      for id, row in pairs(migrations) do
        print(fmt("%s: %s", id, concat(row, ", ")))
      end
    else
      print(fmt("No migrations have been run yet for %s '%s'",
            db_infos.desc, db_infos.name))
    end
  elseif args.command == "reset" then
    if confirm("Are you sure? This operation is irreversible.") then
      dao:drop_schema()
      print("Schema reset")
    else
      print("Canceled")
    end
  end
end

local lapp = [[
Usage: kong migrate COMMAND [OPTIONS]

The available commands are:
 list
 up
 reset

Options:
 -c,--conf (optional string) configuration file
]]

return {
  lapp = lapp,
  execute = execute,
  sub_commands = {up = true, list = true, reset = true}
}
