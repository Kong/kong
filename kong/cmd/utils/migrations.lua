local log = require "kong.cmd.utils.log"


-- TODO: argument so migrations can take more than 60s without other nodes
-- timing out
local MUTEX_TIMEOUT = 60


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


local function bootstrap(schema_state, db)
  if schema_state.needs_bootstrap then
    log("bootstrapping database...")
    assert(db:schema_bootstrap())

  else
    log("database already bootstrapped")
  end

  log("running migrations...")

  local ok, err = db:cluster_mutex("bootstrap", { ttl = MUTEX_TIMEOUT }, function()
    assert(db:run_migrations(schema_state.new_migrations, {
      run_up = true
    }))
    log("database is up-to-date")
  end)
  if err then
    error(err)
  end

  if not ok then
    -- TODO: show this log sooner
    log("another node ran migrations")
  end
end


local function up(schema_state, db)
  if schema_state.needs_bootstrap then
    error("can't run migrations: database needs bootstrapping; " ..
          "run 'kong migrations bootstrap'")
  end

  local ok, err = db:cluster_mutex("migrations", { ttl = MUTEX_TIMEOUT }, function()
    schema_state = assert(db:schema_state())

    if schema_state.pending_migrations then
      error("database has pending migrations; run 'kong migrations finish'")
    end

    if not schema_state.new_migrations then
      log("schema already up-to-date")
      return
    end

    log.debug("migrations to run:\n%s", schema_state.new_migrations)

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

  return ok
end


local function finish(schema_state, db)
  if schema_state.needs_bootstrap then
    log("can't run migrations: database not bootstrapped")
    return
  end

  local ok, err = db:cluster_mutex("migrations", { ttl = MUTEX_TIMEOUT }, function()
    local schema_state = assert(db:schema_state())

    if not schema_state.pending_migrations then
      log("no pending migrations to finish")
      return
    end

    log.debug("pending migrations to finish:\n%s",
              schema_state.pending_migrations)

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


local function reset(db)
  -- TODO: confirmation prompt
  assert(db:schema_reset())
  log("schema reset")
end


return {
  up = up,
  reset = reset,
  finish = finish,
  bootstrap = bootstrap,
  print_state = print_state,
}
