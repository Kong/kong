local DB = require "kong.db"
local log = require "kong.cmd.utils.log"
local tty = require "kong.cmd.utils.tty"
local conf_loader = require "kong.conf_loader"
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
  args.lock_timeout = args.lock_timeout * 1000

  if args.quiet then
    log.disable()
  end

  local conf = assert(conf_loader(args.conf))
  conf.cassandra_timeout = args.db_timeout -- connect + send + read
  conf.cassandra_schema_consensus_timeout = args.db_timeout
  -- TODO: no support for custom pgmoon timeout

  local db = DB.new(conf)
  assert(db:init_connector())

  local schema_state = assert(db:schema_state())

  if args.command == "list" then
    if schema_state.needs_bootstrap then
      log("database needs bootstrapping; run 'kong migrations bootstrap'")
      os.exit(3)
    end

    if schema_state.executed_migrations then
      log("executed migrations:\n%s", schema_state.executed_migrations)
    end

    migrations_utils.print_state(schema_state)

    if schema_state.pending_migrations then
      os.exit(4)
    end

    if schema_state.new_migrations then
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

    migrations_utils.reset(schema_state, db, args.lock_timeout)

  elseif args.command == "up" then
    migrations_utils.up(schema_state, db, {
      ttl = args.lock_timeout,
      abort = true, -- exit the mutex if another node acquired it
    })

  elseif args.command == "finish" then
    migrations_utils.finish(schema_state, db, args.lock_timeout)

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
