local log = require "kong.cmd.utils.log"


local MIGRATIONS_MUTEX_KEY = "migrations"
local NOT_LEADER_MSG = "aborted: another node is performing database changes"


local function print_state(schema_state, lvl)
  local elvl = lvl or "info"

  if schema_state.needs_bootstrap then
    log[elvl]("database needs bootstrapping; run 'kong migrations bootstrap'")
    return
  end

  if schema_state.missing_migrations then
    local mlvl = lvl or "warn"
    log[mlvl]("database is missing some migrations:\n%s",
              schema_state.missing_migrations)
  end

  if schema_state.pending_migrations then
    log[elvl]("database has pending migrations:\n%s",
              schema_state.pending_migrations)
  end

  if schema_state.new_migrations then
    log[elvl]("database has new migrations available:\n%s\n%s",
              schema_state.new_migrations,
              "run 'kong migrations up' to proceed")

  elseif not schema_state.pending_migrations
     and not schema_state.missing_migrations then
    log("database is up-to-date")
  end
end


local function bootstrap(schema_state, db, ttl)
  if schema_state.needs_bootstrap then
    log("bootstrapping database...")
    assert(db:schema_bootstrap())

  else
    log("database already bootstrapped")
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
    log("database is up-to-date")
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
    assert(db:schema_bootstrap())
  end

  local ok, err = db:cluster_mutex(MIGRATIONS_MUTEX_KEY, opts, function()
    schema_state = assert(db:schema_state())

    if schema_state.pending_migrations then
      error("database has pending migrations; run 'kong migrations finish'")
    end

    if not schema_state.new_migrations then
      log("database is already up-to-date")
      return
    end

    log.debug("migrations to run:\n%s", schema_state.new_migrations)

    assert(db:run_migrations(schema_state.new_migrations, {
      run_up = true,
    }))
  end)
  if err then
    error(err)
  end

  if not ok then
    log(NOT_LEADER_MSG)
  end

  return ok
end


local function finish(schema_state, db, ttl)
  if schema_state.needs_bootstrap then
    log("can't run migrations: database not bootstrapped")
    return
  end

  local opts = {
    ttl = ttl,
    no_wait = true, -- exit the mutex if another node acquired it
  }

  local ok, err = db:cluster_mutex(MIGRATIONS_MUTEX_KEY, opts, function()
    local schema_state = assert(db:schema_state())

    if not schema_state.pending_migrations then
      log("no pending migrations to finish")
      return
    end

    log.debug("pending migrations to finish:\n%s",
              schema_state.pending_migrations)

    assert(db:run_migrations(schema_state.pending_migrations, {
      run_teardown = true,
    }))
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
    log("database not bootstrapped, nothing to reset")
    return false
  end

  local opts = {
    ttl = ttl,
    no_wait = true,
    no_cleanup = true,
  }

  local ok, err = db:cluster_mutex(MIGRATIONS_MUTEX_KEY, opts, function()
    log("resetting database...")
    assert(db:schema_reset())
    log("database successfully reset")
  end)
  if err then
    -- failed to acquire locks - maybe locks table was dropped?
    log.error(err .. " - retrying without cluster lock")
    log("resetting database...")
    assert(db:schema_reset())
    log("database successfully reset")
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
  print_state = print_state,
}
