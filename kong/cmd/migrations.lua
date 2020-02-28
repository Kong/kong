local DB = require "kong.db"
local log = require "kong.cmd.utils.log"
local tty = require "kong.cmd.utils.tty"
local meta = require "kong.meta"
local conf_loader = require "kong.conf_loader"
local kong_global = require "kong.global"
local migrations_utils = require "kong.cmd.utils.migrations"


local lapp = [[
Usage: kong migrations COMMAND [OPTIONS]

Manage database schema migrations.

The available commands are:
  bootstrap                         Bootstrap the database and run all
                                    migrations.

  up                                Run any new migrations.

  finish                            Finish running any pending migrations after
                                    'up'.

  list                              List executed migrations.

  reset                             Reset the database.

Options:
 -y,--yes                           Assume "yes" to prompts and run
                                    non-interactively.

 -q,--quiet                         Suppress all output.

 -f,--force                         Run migrations even if database reports
                                    as already executed.

 --db-timeout     (default 60)      Timeout, in seconds, for all database
                                    operations (including schema consensus for
                                    Cassandra).

 --lock-timeout   (default 60)      Timeout, in seconds, for nodes waiting on
                                    the leader node to finish running
                                    migrations.

 -c,--conf        (optional string) Configuration file.

]]


local function confirm_prompt(q)
  local MAX = 3
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

  while MAX > 0 do
    io.write("> " .. q .. " [Y/n] ")
    local a = io.read("*l")
    if ANSWERS[a] ~= nil then
      return ANSWERS[a]
    end
    MAX = MAX - 1
  end
end


local function execute(args)
  args.db_timeout = args.db_timeout * 1000
  args.lock_timeout = args.lock_timeout

  if args.quiet then
    log.disable()
  end

  local conf = assert(conf_loader(args.conf))

  package.path = conf.lua_package_path .. ";" .. package.path

  conf.pg_timeout = args.db_timeout -- connect + send + read

  conf.cassandra_timeout = args.db_timeout -- connect + send + read
  conf.cassandra_schema_consensus_timeout = args.db_timeout

  _G.kong = kong_global.new()
  kong_global.init_pdk(_G.kong, conf, nil) -- nil: latest PDK

  local db = assert(DB.new(conf))
  assert(db:init_connector())

  local schema_state = assert(db:schema_state())

  if args.command == "list" then
    if schema_state.needs_bootstrap then
      log(migrations_utils.NEEDS_BOOTSTRAP_MSG)
      os.exit(3)
    end

    local r = ""

    if schema_state.executed_migrations then
      log("Executed migrations:\n%s", schema_state.executed_migrations)
      r = "\n"
    end

    if schema_state.pending_migrations then
      log("%sPending migrations:\n%s", r, schema_state.pending_migrations)
      r = "\n"
    end

    if schema_state.new_migrations then
      log("%sNew migrations available:\n%s", r, schema_state.new_migrations)
      r = "\n"
    end

    if schema_state.pending_migrations and schema_state.new_migrations then
      if r ~= "" then
        log("")
      end

      log.warn("Database has pending migrations from a previous upgrade, " ..
               "and new migrations from this upgrade (version %s)",
               tostring(meta._VERSION))

      log("\nRun 'kong migrations finish' when ready to complete pending " ..
          "migrations (%s %s will be incompatible with the previous Kong " ..
          "version)", db.strategy, db.infos.db_desc)

      os.exit(4)
    end

    if schema_state.pending_migrations then
      log("\nRun 'kong migrations finish' when ready")
      os.exit(4)
    end

    if schema_state.new_migrations then
      log("\nRun 'kong migrations up' to proceed")
      os.exit(5)
    end

    -- exit(0)

  elseif args.command == "bootstrap" then
    migrations_utils.bootstrap(schema_state, db, args.lock_timeout)

  elseif args.command == "reset" then
    if not args.yes then
      if not tty.isatty() then
        error("not a tty: invoke 'reset' non-interactively with the --yes flag")
      end

      if not confirm_prompt("Are you sure? This operation is irreversible.") then
        log("cancelled")
        return
      end
    end

    local ok = migrations_utils.reset(schema_state, db, args.lock_timeout)
    if not ok then
      os.exit(1)
    end
    os.exit(0)

  elseif args.command == "up" then
    migrations_utils.up(schema_state, db, {
      ttl = args.lock_timeout,
      force = args.force,
      abort = true, -- exit the mutex if another node acquired it
    })

  elseif args.command == "finish" then
    migrations_utils.finish(schema_state, db, {
      ttl = args.lock_timeout,
      force = args.force,
    })

  else
    error("unreachable")
  end
end


return {
  lapp = lapp,
  execute = execute,
  sub_commands = {
    bootstrap = true,
    up = true,
    finish = true,
    list = true,
    reset = true,
  }
}
