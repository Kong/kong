---[==[
local DB = require "kong.db"
local log = require "kong.cmd.utils.log"
local conf_loader = require "kong.conf_loader"


-- TODO: argument so migrations can take more than 60s without other nodes
-- timing out
local MUTEX_TIMEOUT = 60
local CASSANDRA_TIMEOUT = 60000


local lapp = [[
Usage: kong migrations COMMAND [OPTIONS]

Manage Kong's database migrations.

The available commands are:
  check
  bootstrap
  up
  finish
  reset

Options:
  -c,--conf        (optional string) configuration file
]]


local function print_migrations(mig_arr, lvl)
  if not lvl then
    lvl = "info"
  end

  for _, t in ipairs(mig_arr) do
    log[lvl]("%s: %s", t.subsystem, table.concat(t.migrations, ", "))
  end
end


local function check(schema_state)
  -- TODO: -s/-q silent flag
  if schema_state.needs_bootstrap then
    log("needs bootstrap")
    return
  end

  if schema_state.missing_migrations then
    log.warn("missing some migrations:")
    print_migrations(schema_state.missing_migrations, "warn")
  end

  if schema_state.pending_migrations then
    log("pending migrations:")
    print_migrations(schema_state.pending_migrations)
  end

  if schema_state.new_migrations then
    log("new migrations available:")
    print_migrations(schema_state.new_migrations)

  elseif not schema_state.pending_migrations
     and not schema_state.missing_migrations then
    log("schema up-to-date")
  end
end


local function bootstrap(schema_state, db)
  if not schema_state.needs_bootstrap then
    log("database already bootstrapped")
    return
  end

  log("bootstrapping database...")
  assert(db:schema_bootstrap())

  local ok, err = db:cluster_mutex("bootstrap", { ttl = MUTEX_TIMEOUT }, function()
    assert(db:run_migrations(schema_state.new_migrations, {
      run_up = true
    }))
    log("schema up-to-date!")
  end)
  if err then
    error(err)
  end

  if not ok then
    -- TODO: show this log sooner
    log("another node ran migrations")
  end
end


local function reset(db)
  -- TODO: confirmation prompt
  assert(db:schema_reset())
  log("schema reset")
end


local function up_migrations(schema_state, db)
  if schema_state.needs_bootstrap then
      log("can't run migrations: database not bootstrapped")
    return
  end

  local ok, err = db:cluster_mutex("migrations", { ttl = MUTEX_TIMEOUT }, function()
    schema_state = assert(db:schema_state())

    if schema_state.pending_migrations then
      log.error("schema already has pending migrations:")
      print_migrations(schema_state.pending_migrations, "error")
      return
    end

    if not schema_state.new_migrations then
      log("schema already up-to-date")
      return
    end

    log.debug("migrations to run:")
    print_migrations(schema_state.new_migrations, "debug")

    assert(db:run_migrations(schema_state.new_migrations, {
      run_up = true,
      upgrade = true,
    }))
  end)
  if err then
    error(err)
  end

  if not ok then
    -- TODO: show this log sooner
    log("another node ran migrations")
  end

  -- TODO: start nodes?
end


local function finish_migrations(schema_state, db)
  if schema_state.needs_bootstrap then
    log("can't run migrations: database not bootstrapped")
    return
  end

  local ok, err = db:cluster_mutex("migrations", { ttl = MUTEX_TIMEOUT }, function()
    local schema_state = assert(db:schema_state())

    if not schema_state.pending_migrations then
      log("no pending migrations")
      return
    end

    log.debug("pending migrations to finish: ")
    print_migrations(schema_state.pending_migrations, "debug")

    assert(db:run_migrations(schema_state.pending_migrations, {
      run_teardown = true
    }))
  end)
  if err then
    error(err)
  end

  if not ok then
    -- TODO: show this log sooner
    log("another node ran pending migrations")
  end
end


local function execute(args)
  local conf = assert(conf_loader(args.conf))
  conf.cassandra_timeout = CASSANDRA_TIMEOUT -- TODO: separate read_timeout from connect_timeout

  local db = DB.new(conf)
  assert(db:init_connector())

  local schema_state = assert(db:schema_state())

  if args.command == "check" then
    check(schema_state)

  elseif args.command == "bootstrap" then
    bootstrap(schema_state, db)

  elseif args.command == "reset" then
    reset(db)

  elseif args.command == "up" then
    up_migrations(schema_state, db)

  elseif args.command == "finish" then
    finish_migrations(schema_state, db)

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
    -- list
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
