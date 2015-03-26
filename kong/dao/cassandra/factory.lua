local constants = require "kong.constants"
local cassandra = require "cassandra"
local DaoError = require "kong.dao.error"
local stringy = require "stringy"
local Object = require "classic"

local Apis = require "kong.dao.cassandra.apis"
local Metrics = require "kong.dao.cassandra.metrics"
local Plugins = require "kong.dao.cassandra.plugins"
local Consumers = require "kong.dao.cassandra.consumers"
local Applications = require "kong.dao.cassandra.applications"

local CassandraFactory = Object:extend()

local LOCALHOST = "localhost"
local LOCALHOST_IP = "127.0.0.1"

-- Converts every occurence of "localhost" to "127.0.0.1"
-- @param host can either be a string or an array of hosts
local function normalize_localhost(host)
  if type(host) == "table" then
    for i,v in ipairs(host) do
      if v == LOCALHOST then
        host[i] = LOCALHOST_IP
      end
    end
  elseif host == LOCALHOST then
    host = LOCALHOST_IP
  end
  return host
end

-- Instanciate a Cassandra DAO.
-- @param properties Cassandra properties
function CassandraFactory:new(properties, plugins_available)
  self.type = "cassandra"
  self._properties = properties

  -- Convert localhost to 127.0.0.1
  -- This is because nginx doesn't resolve the /etc/hosts file but /etc/resolv.conf
  -- And it may cause errors like "host not found" for "localhost"
  self._properties.hosts = normalize_localhost(self._properties.hosts)

  -- TODO: a metatable to this could prepare all statements as soon as an entry is added
  self.daos = {
    apis = Apis(properties),
    metrics = Metrics(properties),
    plugins = Plugins(properties),
    consumers = Consumers(properties),
    applications = Applications(properties)
  }

  for _, plugin_name in ipairs(plugins_available) do
    local status, res = pcall(require, string.format("kong.plugins.%s.dao.%s", plugin_name, self.type))
    if not status then
      print("No DAO for plugin: "..plugin_name..". "..res)
    else
      local plugin_dao = res()
      table.insert(self.daos, plugin_dao(properties))
    end
  end
end

function CassandraFactory:drop()
  return self:execute_queries [[
    TRUNCATE apis;
    TRUNCATE metrics;
    TRUNCATE plugins;
    TRUNCATE consumers;
    TRUNCATE applications;
  ]]
end

-- Prepare all statements in collection._queries and put them in collection._statements.
-- Should be called with only a collection and will recursively call itself for nested statements.
-- @param collection A collection with a ._queries property
local function prepare_collection(collection, queries, statements)
  if not queries then queries = collection._queries end
  if not statements then statements = collection._statements end

  for stmt_name, query in pairs(queries) do
    if type(query) == "table" and query.query == nil then
      collection._statements[stmt_name] = {}
      prepare_collection(collection, query, collection._statements[stmt_name])
    else
      local q = stringy.strip(query.query)
      q = string.format(q, "")
      local kong_stmt, err = collection:prepare_kong_statement(q, query.params)
      if err then
        error(err)
      end
      statements[stmt_name] = kong_stmt
    end
  end
end

-- Prepare all statements of collections
-- @return error if any
function CassandraFactory:prepare()
  for _, dao in pairs(self.daos) do
    local status, err = pcall(prepare_collection, dao)
    if not status then
      return err
    end
  end
end

-- Execute a string of queries separated by ;
-- Useful for huge DDL operations such as migrations
-- @param {string} queries Semicolon separated string of queries
-- @param {boolean} no_keyspace Won't set the keyspace if true
-- @return {string} error if any
function CassandraFactory:execute_queries(queries, no_keyspace)
  local ok, err
  local session = cassandra.new()
  session:set_timeout(self._properties.timeout)

  ok, err = session:connect(self._properties.hosts, self._properties.port)
  if not ok then
    return DaoError(err, constants.DATABASE_ERROR_TYPES.DATABASE)
  end

  if no_keyspace == nil then
    ok, err = session:set_keyspace(self._properties.keyspace)
    if not ok then
      return DaoError(err, constants.DATABASE_ERROR_TYPES.DATABASE)
    end
  end

  -- Cassandra only supports BATCH on DML statements.
  -- We must split commands to execute them individually for migrations and such
  queries = stringy.split(queries, ";")
  for _, query in ipairs(queries) do
    if stringy.strip(query) ~= "" then
      local _, stmt_err = session:execute(query)
      if stmt_err then
        return DaoError(stmt_err, constants.DATABASE_ERROR_TYPES.DATABASE)
      end
    end
  end

  session:close()
end

--
-- Migrations
--

local MIGRATION_IDENTIFIER = "migrations"

-- Create a cassandra session and execute a query on given keyspace or default one (from properties).
-- @param query Query or prepared statement given to session:execute
-- @param params List of parameters given to session:execute
-- @param keyspace Optional: overrides properties keyspace if specified
-- @return query result
-- @return error if any
function CassandraFactory:execute(query, params, keyspace)
  local ok, err
  local session = cassandra.new()
  session:set_timeout(self._properties.timeout)

  ok, err = session:connect(self._properties.hosts, self._properties.port)
  if not ok then
    return nil, DaoError(err, constants.DATABASE_ERROR_TYPES.DATABASE)
  end

  ok, err = session:set_keyspace(keyspace and keyspace or self._properties.keyspace)
  if not ok then
    return nil, DaoError(err, constants.DATABASE_ERROR_TYPES.DATABASE)
  end

  ok, err = session:execute(query, params)

  session:close()

  return ok, DaoError(err, constants.DATABASE_ERROR_TYPES.DATABASE)
end

-- Log (add) given migration to schema_migrations table.
-- @param migration_name Name of the migration to log
-- @return query result
-- @return error if any
function CassandraFactory:add_migration(migration_name)
  return self:execute("UPDATE schema_migrations SET migrations = migrations + ? WHERE id = ?",
                      { cassandra.list({ migration_name }), MIGRATION_IDENTIFIER })
end

-- Return all logged migrations if any. Check if keyspace exists before to avoid error during the first migration.
-- @return A list of previously executed migration (as strings)
-- @return error if any
function CassandraFactory:get_migrations()
  local rows, err

  rows, err = self:execute("SELECT * FROM schema_keyspaces WHERE keyspace_name = ?", { self._properties.keyspace }, "system")
  if err then
    return nil, err
  elseif #rows == 0 then
    -- keyspace is not yet created, this is the first migration
    return nil
  end

  rows, err = self:execute("SELECT migrations FROM schema_migrations WHERE id = ?", { MIGRATION_IDENTIFIER })
  if err then
    return nil, err
  elseif rows and #rows > 0 then
    return rows[1].migrations
  end
end

-- Unlog (delete) given migration from the schema_migrations table.
-- @return query result
-- @return error if any
function CassandraFactory:delete_migration(migration_name)
  return self:execute("UPDATE schema_migrations SET migrations = migrations - ? WHERE id = ?",
                      { cassandra.list({ migration_name }), MIGRATION_IDENTIFIER })
end

return CassandraFactory
