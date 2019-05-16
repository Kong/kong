local log = require "kong.cmd.utils.log"


local fmt = string.format


local MIGRATIONS_MUTEX_KEY = "migrations"
local NOT_LEADER_MSG = "aborted: another node is performing database changes"


local function check_state(schema_state, db)
  if not schema_state:is_up_to_date() then
    if schema_state.needs_bootstrap then
      if schema_state.legacy_invalid_state then
        error(fmt("Cannot start Kong 1.x with a legacy %s, upgrade to 0.14 " ..
                  "first, and run 'kong migrations up'", db.infos.db_desc))
      end

      if not schema_state.legacy_is_014 then
        error("Database needs bootstrapping; run 'kong migrations bootstrap'")
      end
    end

    if schema_state.new_migrations then
      error("New migrations available; run 'kong migrations up' to proceed")
    end
  end
end

local function bootstrap(schema_state, db, ttl)
  if schema_state.needs_bootstrap then
    if schema_state.legacy_is_014 then
      error(fmt("Cannot bootstrap a non-empty %s, run 'kong migrations " ..
                "up' instead", db.infos.db_desc))
    end

    if schema_state.legacy_invalid_state then
      error(fmt("Cannot bootstrap a non-empty %s, upgrade to 0.14 first, " ..
                "and run 'kong migrations up'", db.infos.db_desc))
    end

    log("Bootstrapping database...")
    assert(db:schema_bootstrap())

  else
    log("Database already bootstrapped")
    return
  end

  local opts = {
    ttl = ttl,
    no_wait = true, -- exit the mutex if another node acquired it
  }

  local ok, err = db:cluster_mutex(MIGRATIONS_MUTEX_KEY, opts, function()
    assert(db:run_migrations(schema_state.new_migrations, {
      run_up = true,
      run_teardown = true,
    }))
    log("Database is up-to-date")
  end)
  if err then
    error(err)
  end

  if not ok then
    log(NOT_LEADER_MSG)
  end
end


local function up(schema_state, db, opts)
  if schema_state.needs_bootstrap then
    if schema_state.legacy_invalid_state then
      -- legacy: migration from 0.14 to 1.0 cannot be performed
      if schema_state.legacy_missing_component then
        error(fmt("Migration to 1.0 can only be performed from a 0.14 %s " ..
                  "%s, but the current %s seems to be older (missing "     ..
                  "migrations for '%s'). Migrate to 0.14 first, or "       ..
                  "install 1.0 on a fresh %s", db.strategy, db.infos.db_desc,
                  db.infos.db_desc, schema_state.legacy_missing_component,
                  db.infos.db_desc))
      end

      if schema_state.legacy_missing_migration then
        error(fmt("Migration to 1.0 can only be performed from a 0.14 %s " ..
                  "%s, but the current %s seems to be older (missing "     ..
                  "migration '%s' for '%s'). Migrate to 0.14 first, or "   ..
                  "install 1.0 on a fresh %s", db.strategy, db.infos.db_desc,
                  db.infos.db_desc, schema_state.legacy_missing_migration,
                  schema_state.legacy_missing_component, db.infos.db_desc))
      end

      error(fmt("Migration to 1.0 can only be performed from a 0.14 %s " ..
                "%s, but the current %s seems to be older (missing "     ..
                "migrations). Migrate to 0.14 first, or install 1.0 "    ..
                "on a fresh %s", db.strategy, db.infos.db_desc,
                db.infos.db_desc, db.infos.db_desc))
    end

    if schema_state.legacy_is_014 then
      local present, err = db:are_014_apis_present()
      if err then
        error(err)
      end

      if present then
        error("Cannot run migrations: you have `api` entities in your database; " ..
              "please convert them to `routes` and `services` prior to " ..
              "migrating to Kong 1.0")
      end

      -- legacy: migration from 0.14 to 1.0 can be performed
      log("Upgrading from 0.14, bootstrapping database...")
      assert(db:schema_bootstrap())

    else
      -- fresh install: must bootstrap (which will run migrations up)
      error("Cannot run migrations: database needs bootstrapping; " ..
            "run 'kong migrations bootstrap'")
    end
  end

  local ok, err = db:cluster_mutex(MIGRATIONS_MUTEX_KEY, opts, function()
    schema_state = assert(db:schema_state())

    if not opts.force and schema_state.pending_migrations then
      error("Database has pending migrations; run 'kong migrations finish'")
    end

    if opts.force and schema_state.executed_migrations then
      log.debug("forcing re-execution of these migrations:\n%s",
                schema_state.executed_migrations)

      assert(db:run_migrations(schema_state.executed_migrations, {
        run_up = true,
        run_teardown = true,
        skip_teardown_migrations = schema_state.pending_migrations
      }))

      schema_state = assert(db:schema_state())
      if schema_state.pending_migrations then
        log("\nDatabase has pending migrations; run 'kong migrations finish' when ready")
        return
      end
    end

    if not schema_state.new_migrations then
      if not opts.force then
        log("Database is already up-to-date")
      end

      return
    end

    log.debug("migrations to run:\n%s", schema_state.new_migrations)

    assert(db:run_migrations(schema_state.new_migrations, {
      run_up = true,
    }))

    schema_state = assert(db:schema_state())
    if schema_state.pending_migrations then
      log("\nDatabase has pending migrations; run 'kong migrations finish' when ready")
      return
    end
  end)
  if err then
    error(err)
  end

  if not ok then
    log(NOT_LEADER_MSG)
  end

  return ok
end


local function finish(schema_state, db, opts)
  if schema_state.needs_bootstrap then
    if schema_state.legacy_invalid_state then
      -- legacy: migration from 0.14 to 1.0 cannot be performed
      error(fmt("Cannot run migrations on a legacy %s", db.infos.db_desc))
    end

    if schema_state.legacy_is_014 then
      error(fmt("Cannot run migrations on a legacy %s; run 'kong " ..
                "migrations up' to proceed", db.infos.db_desc))
    end

    error("Cannot run migrations; run 'kong migrations bootstrap' instead")
  end

  opts.no_wait = true -- exit the mutex if another node acquired it

  local ok, err = db:cluster_mutex(MIGRATIONS_MUTEX_KEY, opts, function()
    local schema_state = assert(db:schema_state())

    if opts.force and schema_state.executed_migrations then
      assert(db:run_migrations(schema_state.executed_migrations, {
        run_up = true,
        run_teardown = true,
      }))

      schema_state = assert(db:schema_state())
    end

    if schema_state.pending_migrations then
      log.debug("pending migrations to finish:\n%s",
                schema_state.pending_migrations)

      assert(db:run_migrations(schema_state.pending_migrations, {
        run_teardown = true,
      }))

      schema_state = assert(db:schema_state())
    end

    if schema_state.new_migrations then
      log("\nNew migrations available; run 'kong migrations up' to proceed")
      return
    end

    if not opts.force and not schema_state.pending_migrations then
      log("No pending migrations to finish")
    end

    return
  end)
  if err then
    error(err)
  end

  if not ok then
    log(NOT_LEADER_MSG)
  end
end


local function reset(schema_state, db, ttl)
  if schema_state.needs_bootstrap then
    log("Database not bootstrapped, nothing to reset")
    return false
  end

  local opts = {
    ttl = ttl,
    no_wait = true,
    no_cleanup = true,
  }

  local ok, err = db:cluster_mutex(MIGRATIONS_MUTEX_KEY, opts, function()
    log("Resetting database...")
    assert(db:schema_reset())
    log("Database successfully reset")
  end)
  if err then
    -- failed to acquire locks - maybe locks table was dropped?
    log.error(err .. " - retrying without cluster lock")
    log("Resetting database...")
    assert(db:schema_reset())
    log("Database successfully reset")
    return true
  end

  if not ok then
    log(NOT_LEADER_MSG)
    return false
  end
  return true
end


return {
  up = up,
  reset = reset,
  finish = finish,
  bootstrap = bootstrap,
  check_state = check_state,
}
