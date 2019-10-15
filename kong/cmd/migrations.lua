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

  migrate-apis                      Migrates API entities to Routes and
                                    Services.

  migrate-community-to-enterprise   Migrates CE entities to EE on the default
                                    workspace

  reinitialize-workspace-entity-counters  Resets the entity counters from the
                                          database entities.

Options:
 -y,--yes                           Assume "yes" to prompts and run
                                    non-interactively.

 -q,--quiet                         Suppress all output.

 -f,--force                         Run migrations even if database reports
                                    as already executed.

                                    With 'migrate-apis' command, it also forces
                                    migration of APIs that have custom plugins
                                    applied, and which are otherwise skipped.

                                    With 'migrate-community-to-enterprise' it
                                    disables the workspace entities check.

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
      if schema_state.legacy_invalid_state then
        -- legacy: migration from 0.14 to 1.0 cannot be performed
        if schema_state.legacy_missing_component then
          log("Migrations can only be listed on a %s %s that has been " ..
              "upgraded to 1.0, but the current %s seems to be older "  ..
              "than 0.14 (missing migrations for '%s')",
              db.strategy, db.infos.db_desc, db.infos.db_desc,
              schema_state.legacy_missing_component)

          os.exit(2)
        end

        if schema_state.legacy_missing_migration then
          log("Migrations can only be listed on a %s %s that has been " ..
              "upgraded to 1.0, but the current %s seems to be older "  ..
              "than 0.14 (missing migration '%s' for '%s')",
              db.strategy, db.infos.db_desc, db.infos.db_desc,
              schema_state.legacy_missing_migration,
              schema_state.legacy_missing_component)

          os.exit(2)
        end

        log("Migrations can only be listed on a %s %s that has been "     ..
            "upgraded to 1.0, but the current %s seems to be older than " ..
            "0.14 (missing migrations)", db.strategy, db.infos.db_desc,
            db.infos.db_desc)

        os.exit(2)

      elseif not schema_state.legacy_is_014 then
        log("Database needs bootstrapping; run 'kong migrations bootstrap'")
        os.exit(3)
      end
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

    if schema_state.needs_bootstrap then
      os.exit(3)
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

  elseif args.command == "migrate-apis" then
    migrations_utils.migrate_apis(schema_state, db, {
      ttl = args.lock_timeout,
      force = args.force,
    })

  elseif args.command == "migrate-community-to-enterprise" then
    if not args.yes then
      if not tty.isatty() then
        error("not a tty: invoke 'reset' non-interactively with the --yes flag")
      end

      if not confirm_prompt("Are you sure? This operation is irreversible." ..
                          " Confirm you have a backup of your production data") then
        log("cancelled")
        return
      end
    end

    local _, err = migrations_utils.migrate_core_entities(schema_state, db, {
      ttl = args.lock_timeout,
      force = args.force,
      conf = args.conf,
    })
    if err then
      error(err)
    end

  elseif args.command == "reinitialize-workspace-entity-counters" then
    local counters = require "kong.workspaces.counters"
    counters.initialize_counters(db)

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
    ["migrate-apis"] = true,
    ["migrate-community-to-enterprise"] = true,
    ["reinitialize-workspace-entity-counters"]=true,
  }
}
