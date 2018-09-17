local DAO          = require "kong.db.dao"
local Entity       = require "kong.db.schema.entity"
local Errors       = require "kong.db.errors"
local Strategies   = require "kong.db.strategies"
local MetaSchema   = require "kong.db.schema.metaschema"


local fmt          = string.format
local type         = type
local pairs        = pairs
local error        = error
local ipairs       = ipairs
local rawget       = rawget
local setmetatable = setmetatable


-- maybe a temporary constant table -- could be move closer
-- to schemas and entities since schemas will also be used
-- independently from the DB module (Admin API for GUI)
-- Notice that the order in which they are listed is important:
-- schemas of dependencies need to be loaded first.
local CORE_ENTITIES = {
  "consumers",
  "services",
  "routes",
  "certificates",
  "snis",
  "upstreams",
  "targets",
  "apis",
  "plugins",
}


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

    for _, entity_name in ipairs(CORE_ENTITIES) do
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
  return "[" .. self.strategy .. " error] " .. err
end


function DB:init_connector()
  -- I/O with the DB connector singleton
  -- Implementation up to the strategy's connector. A place for:
  --   - connection check
  --   - cluster retrievel (cassandra)
  --   - prepare statements
  --   - nop (default)

  local ok, err = self.connector:init()
  if not ok then
    return nil, prefix_err(self, err)
  end

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
  local public = require "kong.tools.public"
  local resty_lock = require "resty.lock"


  local DEFAULT_TTL = 60 -- seconds
  local MAX_LOCK_WAIT_STEP = 2 -- seconds


  local function release_rlock_and_ret(rlock, ...)
    rlock:unlock()

    return ...
  end


  function DB:cluster_mutex(key, opts, cb)
    if type(key) ~= "string" then
      error("key must be a string", 2)
    end

    local owner
    local ttl

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

      owner = opts.owner
      ttl = opts.ttl
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
      -- we use the `get_node_id()` public utility, but in the CLI context,
      -- this value is ephemeral, so no assumptions should be made about the
      -- real owner of a lock
      local id, err = public.get_node_id()
      if not id then
        return nil, "failed to generate lock owner: " .. err
      end

      owner = id
    end

    if not ttl then
      ttl = DEFAULT_TTL
    end

    local rlock, err = resty_lock:new("kong_locks", {
      exptime = ttl,
      timeout = ttl,
    })
    if not rlock then
      return nil, "failed to create worker lock: " .. err
    end

    -- acquire a single worker

    local elapsed, err = rlock:lock(key)
    if not elapsed then
      if err == "timeout" then
        return nil, err
      end

      return nil, "failed to acquire worker lock: " .. err
    end

    if elapsed ~= 0 then
      -- we did not acquire the worker lock, but it was released
      return false
    end

    -- worker lock acquired, other workers are waiting on it
    -- now acquire cluster lock via strategy-specific connector

    -- ensure the locks table exists
    local ok, err = self.connector:setup_locks(DEFAULT_TTL)
    if not ok then
      return release_rlock_and_ret(rlock, nil,
                                   "failed to setup locks: " .. err)
    end

    local ok, err = self.connector:insert_lock(key, ttl, owner)
    if err then
      return release_rlock_and_ret(rlock, nil,
                                   "failed to insert cluster lock: " .. err)
    end

    if not ok then
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
          return release_rlock_and_ret(rlock, nil, "failed to read cluster " ..
                                                   "lock: " .. err)
        end

        if not locked then
          -- the cluster lock was released
          return release_rlock_and_ret(rlock, false)
        end

        step = math.min(step * 3, MAX_LOCK_WAIT_STEP)
      end

      return release_rlock_and_ret(rlock, nil, "timeout")
    end

    -- cluster lock acquired, run callback

    local pok, perr = xpcall(cb, debug.traceback)
    if not pok then
      self.connector:remove_lock(key, owner)

      return release_rlock_and_ret(rlock, nil, "cluster_mutex callback " ..
                                   "threw an error: " .. perr)
    end

    self.connector:remove_lock(key, owner)

    return release_rlock_and_ret(rlock, true)
  end
end


return DB
