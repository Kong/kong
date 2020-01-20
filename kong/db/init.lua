local DAO          = require "kong.db.dao"
local Entity       = require "kong.db.schema.entity"
local Errors       = require "kong.db.errors"
local Strategies   = require "kong.db.strategies"
local MetaSchema   = require "kong.db.schema.metaschema"
local constants    = require "kong.constants"
local log          = require "kong.cmd.utils.log"
local utils        = require "kong.tools.utils"


local fmt          = string.format
local type         = type
local pairs        = pairs
local error        = error
local ipairs       = ipairs
local rawget       = rawget
local setmetatable = setmetatable


local DEFAULT_LOCKS_TTL = 60 -- seconds


local DB = {}
DB.__index = function(self, k)
  return DB[k] or rawget(self, "daos")[k]
end


function DB.new(kong_config, strategy)
  if not kong_config then
    error("missing kong_config", 2)
  end

  if strategy ~= nil and type(strategy) ~= "string" then
    error("strategy must be a string", 2)
  end

  strategy = strategy or kong_config.database

  -- load errors

  local errors = Errors.new(strategy)

  local schemas = {}

  do
    -- load schemas
    -- core entities are for now the only source of schemas.
    -- TODO: support schemas from plugins entities as well.

    for _, entity_name in ipairs(constants.CORE_ENTITIES) do
      local entity_schema = require("kong.db.schema.entities." .. entity_name)

      -- validate core entities schema via metaschema
      local ok, err_t = MetaSchema:validate(entity_schema)
      if not ok then
        return nil, fmt("schema of entity '%s' is invalid: %s", entity_name,
                        tostring(errors:schema_violation(err_t)))
      end
      local entity, err = Entity.new(entity_schema)
      if not entity then
        return nil, fmt("schema of entity '%s' is invalid: %s", entity_name,
                        err)
      end
      schemas[entity_name] = entity

      -- load core entities subschemas
      local subschemas
      ok, subschemas = utils.load_module_if_exists("kong.db.schema.entities." .. entity_name .. "_subschemas")
      if ok then
        for name, subschema in pairs(subschemas) do
          local ok, err = entity:new_subschema(name, subschema)
          if not ok then
            return nil, ("error initializing schema for %s: %s"):format(entity_name, err)
          end
        end
      end
    end
  end

  -- load strategy

  local connector, strategies, err = Strategies.new(kong_config, strategy,
                                                    schemas, errors)
  if err then
    return nil, err
  end

  local daos = {}

  local self   = {
    daos       = daos,       -- each of those has the connector singleton
    strategies = strategies,
    connector  = connector,
    strategy   = strategy,
    errors     = errors,
    infos      = connector:infos(),
    kong_config = kong_config,
  }

  do
    -- load DAOs

    for _, schema in pairs(schemas) do
      local strategy = strategies[schema.name]
      if not strategy then
        return nil, fmt("no strategy found for schema '%s'", schema.name)
      end
      daos[schema.name] = DAO.new(self, schema, strategy, errors)
    end
  end

  -- we are 200 OK


  return setmetatable(self, DB)
end


local function prefix_err(self, err)
  return "[" .. self.infos.strategy .. " error] " .. err
end


local function fmt_err(self, err, ...)
  return prefix_err(self, fmt(err, ...))
end


function DB:init_connector()
  -- I/O with the DB connector singleton
  -- Implementation up to the strategy's connector. A place for:
  --   - connection check
  --   - cluster retrieval (cassandra)
  --   - prepare statements
  --   - nop (default)

  local ok, err = self.connector:init()
  if not ok then
    return nil, prefix_err(self, err)
  end

  self.infos = self.connector:infos()

  return ok
end


function DB:init_worker()
  -- Can be used to implement e.g. a timer jobs to
  -- clean expired records from database in case the
  -- database doesn't natively support TTL, such as
  -- PostgreSQL
  local ok, err = self.connector:init_worker(self.strategies)
  if not ok then
    return nil, prefix_err(self, err)
  end

  return ok
end


function DB:connect()
  local ok, err = self.connector:connect()
  if not ok then
    return nil, prefix_err(self, err)
  end

  return ok
end


function DB:setkeepalive()
  local ok, err = self.connector:setkeepalive()
  if not ok then
    return nil, prefix_err(self, err)
  end

  return ok
end


function DB:close()
  local ok, err = self.connector:close()
  if not ok then
    return nil, prefix_err(self, err)
  end

  return ok
end


function DB:reset()
  local ok, err = self.connector:reset()
  if not ok then
    return nil, prefix_err(self, err)
  end

  return ok
end


function DB:truncate(table_name)
  if table_name ~= nil and type(table_name) ~= "string" then
    error("table_name must be a string", 2)
  end
  local ok, err

  if table_name then
    ok, err = self.connector:truncate_table(table_name)
  else
    ok, err = self.connector:truncate()
  end

  if not ok then
    return nil, prefix_err(self, err)
  end

  return ok
end


function DB:set_events_handler(events)
  for _, dao in pairs(self.daos) do
    dao.events = events
  end
end


do
  local concurrency = require "kong.concurrency"

  local knode = (kong and kong.node) and kong.node or
                require "kong.pdk.node".new()


  local MAX_LOCK_WAIT_STEP = 2 -- seconds


  function DB:cluster_mutex(key, opts, cb)
    if type(key) ~= "string" then
      error("key must be a string", 2)
    end

    local owner
    local ttl
    local no_wait
    local no_cleanup

    if opts ~= nil then
      if type(opts) ~= "table" then
        error("opts must be a table", 2)
      end

      if opts.ttl and type(opts.ttl) ~= "number" then
        error("opts.ttl must be a number", 2)
      end

      if opts.owner and type(opts.owner) ~= "string" then
        error("opts.owner must be a string", 2)
      end

      if opts.no_wait and type(opts.no_wait) ~= "boolean" then
        error("opts.no_wait must be a boolean", 2)
      end

      if opts.no_cleanup and type(opts.no_cleanup) ~= "boolean" then
        error("opts.no_cleanup must be a boolean", 2)
      end

      owner = opts.owner
      ttl = opts.ttl
      no_wait = opts.no_wait
      no_cleanup = opts.no_cleanup
    end

    if type(cb) ~= "function" then
      local mt = getmetatable(cb)

      if not mt or type(mt.__call) ~= "function" then
        error("cb must be a function", 2)
      end
    end

    if not owner then
      -- generate a random string for this worker (resty-cli or runtime nginx
      -- worker)
      --
      -- we use the `node.get_id()` from pdk, but in the CLI context, this
      -- value is ephemeral, so no assumptions should be made about the real
      -- owner of a lock
      local id, err = knode.get_id()
      if not id then
        return nil, prefix_err(self, "failed to generate lock owner: " .. err)
      end

      owner = id
    end

    if not ttl then
      ttl = DEFAULT_LOCKS_TTL
    end

    local mutex_opts = {
      name = key,
      timeout = ttl,
    }
    return concurrency.with_worker_mutex(mutex_opts, function(elapsed)
      if elapsed ~= 0 then
        -- we did not acquire the worker lock, but it was released
        return false
      end

      -- worker lock acquired, other workers are waiting on it
      -- now acquire cluster lock via strategy-specific connector

      local ok, err = self.connector:insert_lock(key, ttl, owner)
      if err then
        return nil, prefix_err(self, "failed to insert cluster lock: " .. err)
      end

      if not ok then
        if no_wait then
          -- don't wait on cluster locked
          return false
        end

        -- waiting on cluster lock
        local step = 0.1
        local cluster_elapsed = 0

        while cluster_elapsed < ttl do
          ngx.sleep(step)
          cluster_elapsed = cluster_elapsed + step

          if cluster_elapsed >= ttl then
            break
          end

          local locked, err = self.connector:read_lock(key)
          if err then
            return nil, prefix_err(self, "failed to read cluster lock: " .. err)
          end

          if not locked then
            -- the cluster lock was released
            return false
          end

          step = math.min(step * 3, MAX_LOCK_WAIT_STEP)
        end

        return nil, prefix_err(self, "timeout")
      end

      -- cluster lock acquired, run callback

      local pok, perr = xpcall(cb, debug.traceback)
      if not pok then
        self.connector:remove_lock(key, owner)

        return nil, prefix_err(self, "cluster_mutex callback threw an error: "
                                     .. perr)
      end

      if not no_cleanup then
        self.connector:remove_lock(key, owner)
      end

      return true
    end)
  end
end


do
  -- migrations
  local utils = require "kong.tools.utils"
  local MigrationHelpers = require "kong.db.migrations.helpers"
  local MigrationsState = require "kong.db.migrations.state"


  local last_schema_state


  function DB:schema_state()
    local err
    last_schema_state, err = MigrationsState.load(self)
    return last_schema_state, err
  end


  function DB:last_schema_state()
    return last_schema_state or self:schema_state()
  end


  function DB:schema_bootstrap()
    local ok, err = self.connector:connect_migrations({ no_keyspace = true })
    if not ok then
      return nil, prefix_err(self, err)
    end

    local ok, err = self.connector:schema_bootstrap(self.kong_config,
                                                    DEFAULT_LOCKS_TTL)

    self.connector:close()

    if not ok then
      return nil, prefix_err(self, "failed to bootstrap database: " .. err)
    end

    return true
  end


  function DB:schema_reset()
    local ok, err = self.connector:connect_migrations({ no_keyspace = true })
    if not ok then
      return nil, prefix_err(self, err)
    end

    local ok, err = self.connector:schema_reset()

    self.connector:close()

    if not ok then
      return nil, prefix_err(self, err)
    end

    return true
  end


  function DB:run_migrations(migrations, options)
    if type(migrations) ~= "table" then
      error("migrations must be a table", 2)
    end

    if type(options) ~= "table" then
      error("options must be a table", 2)
    end

    local run_up = options.run_up
    local run_teardown = options.run_teardown

    local skip_teardown_migrations = {}
    if run_teardown and options.skip_teardown_migrations then
      for _, t in ipairs(options.skip_teardown_migrations) do
        for _, mig in ipairs(t.migrations) do
          local ok, mod = utils.load_module_if_exists(t.namespace .. "." ..
                                                      mig.name)
          if ok then
            local strategy_migration = mod[self.strategy]
            if strategy_migration and strategy_migration.teardown then
              if not skip_teardown_migrations[t.subsystem] then
                skip_teardown_migrations[t.subsystem] = {}
              end

              skip_teardown_migrations[t.subsystem][mig.name] = true
            end
          end
        end
      end
    end

    if not run_up and not run_teardown then
      error("options.run_up or options.run_teardown must be given", 2)
    end

    local ok, err = self.connector:connect_migrations()
    if not ok then
      return nil, prefix_err(self, err)
    end

    local mig_helpers = MigrationHelpers.new(self.connector)

    local n_migrations = 0
    local n_pending = 0

    for i, t in ipairs(migrations) do
      log("migrating %s on %s '%s'...", t.subsystem, self.infos.db_desc,
          self.infos.db_name)

      for _, mig in ipairs(t.migrations) do
        local ok, mod = utils.load_module_if_exists(t.namespace .. "." ..
                                                    mig.name)
        if not ok then
          self.connector:close()
          return nil, fmt_err(self, "failed to load migration '%s': %s",
                              mig.name, mod)
        end

        local strategy_migration = mod[self.strategy]
        if not strategy_migration then
          self.connector:close()
          return nil, fmt_err(self, "missing %s strategy for migration '%s'",
                              self.strategy, mig.name)
        end

        log.debug("running migration: %s", mig.name)

        if run_up then
          -- kong migrations bootstrap
          -- kong migrations up
          ok, err = self.connector:run_up_migration(mig.name,
                                                    strategy_migration.up)
          if not ok then
            self.connector:close()
            return nil, fmt_err(self, "failed to run migration '%s' up: %s",
                                mig.name, err)
          end

          local state = "executed"
          if strategy_migration.teardown then
            -- this migration has a teardown step for later
            state = "pending"
            n_pending = n_pending + 1
          end

          ok, err = self.connector:record_migration(t.subsystem, mig.name,
                                                    state)
          if not ok then
            self.connector:close()
            return nil, fmt_err(self, "failed to record migration '%s': %s",
                                mig.name, err)
          end
        end

        local skip_teardown = skip_teardown_migrations[t.subsystem] and
                              skip_teardown_migrations[t.subsystem][mig.name]

        if not skip_teardown and run_teardown and strategy_migration.teardown then
          if run_up then
            -- ensure schema consensus is reached before running DML queries
            -- that could span all peers
            ok, err = self.connector:wait_for_schema_consensus()
            if not ok then
              self.connector:close()
              return nil, prefix_err(self, err)
            end
          end

          -- kong migrations teardown
          local f = strategy_migration.teardown

          local pok, perr, err = xpcall(f, debug.traceback, self.connector,
                                        mig_helpers)
          if not pok or err then
            self.connector:close()
            return nil, fmt_err(self, "failed to run migration '%s' teardown: %s",
                                mig.name, perr or err)
          end

          ok, err = self.connector:record_migration(t.subsystem, mig.name,
                                                    "teardown")
          if not ok then
            self.connector:close()
            return nil, fmt_err(self, "failed to record migration '%s': %s",
                                mig.name, err)
          end

          n_pending = math.max(n_pending - 1, 0)

          if not run_up then
            -- ensure schema consensus is reached when the next migration to
            -- run will execute its teardown step, since it may make further
            -- DML queries; if the next migration runs its up step, it will
            -- run DDL queries against the same node, so no need to reach
            -- schema consensus
            ok, err = self.connector:wait_for_schema_consensus()
            if not ok then
              self.connector:close()
              return nil, prefix_err(self, err)
            end
          end
        end

        log("%s migrated up to: %s %s", t.subsystem, mig.name,
            strategy_migration.teardown and not run_teardown and "(pending)"
                                                              or "(executed)")

        n_migrations = n_migrations + 1
      end

      if run_up and i == #migrations then
        -- wait for schema consensus after the last migration has run
        -- (only if `run_up`, since if not, we just called it from the
        -- teardown step)
        ok, err = self.connector:wait_for_schema_consensus()
        if not ok then
          self.connector:close()
          return nil, prefix_err(self, err)
        end
      end
    end

    log("%d migration%s processed", n_migrations,
        n_migrations > 1 and "s" or "")

    local n_executed = n_migrations - n_pending

    if n_executed > 0 then
      log("%d executed", n_executed)
    end

    if n_pending > 0 then
      log("%d pending", n_pending)
    end

    self.connector:close()

    return true
  end

  function DB:run_api_migrations(opts)
    local ok, err = self.connector:connect_migrations()
    if not ok then
      return nil, prefix_err(self, err)
    end

    return self.connector:run_api_migrations(opts)
  end


  --[[
  function DB:load_pending_migrations(migrations)
    if type(migrations) ~= "table" then
      error("migrations must be a table", 2)
    end

    for _, t in ipairs(migrations) do
      for _, mig in ipairs(t.migrations) do
        local ok, mod = utils.load_module_if_exists(t.namespace .. "." ..
                                                    mig.name)
        if not ok then
          return nil, fmt("failed to load migration '%s': %s", mig.name,
                          mod)
        end

        if mod.translations then
          ngx.log(ngx.INFO, "loading translation functions for migration ",
                            "'", mig.name, "'")

          for _, translation in ipairs(mod.translations) do
            local dao = self.daos[translation.entity]
            if not dao then
              return nil, fmt("failed to load translation function for " ..
                              "migration '%s': no '%s' DAO exists", mig.name,
                              translation.entity)
            end

            dao:load_translations(mod.translations)
          end
        end
      end
    end

    self.connector:close()

    return true
  end
  --]]
end


return DB
