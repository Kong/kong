-- Kong's cassandra Factory DAO. Entry-point for retrieving DAO objects that allow
-- interations with the database for entities (APIs, Consumers...).
--
-- Also provides helper methods for preparing queries among the DAOs, migrating the
-- database and dropping it.

local constants = require "kong.constants"
local cassandra = require "cassandra"
local DaoError = require "kong.dao.error"
local stringy = require "stringy"
local Object = require "classic"

local Apis = require "kong.dao.cassandra.apis"
local Consumers = require "kong.dao.cassandra.consumers"
local PluginsConfigurations = require "kong.dao.cassandra.plugins_configurations"
local Migrations = require "kong.dao.cassandra.migrations"
local BasicAuthCredentials = require "kong.dao.cassandra.basicauth_credentials"
local RateLimitingMetrics = require "kong.dao.cassandra.ratelimiting_metrics"
local KeyAuthCredentials = require "kong.dao.cassandra.keyauth_credentials"
local DataUsageMetrics = require "kong.dao.cassandra.datausage_metrics"

local CassandraFactory = Object:extend()

local LOCALHOST = "localhost"
local LOCALHOST_IP = "127.0.0.1"

-- Converts every occurence of "localhost" to "127.0.0.1"
-- @param host can either be a string or an array of hosts
local function normalize_localhost(host)
  if type(host) == "table" then
    for i, v in ipairs(host) do
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
function CassandraFactory:new(properties)
  self.type = "cassandra"
  self._properties = properties

  -- Convert localhost to 127.0.0.1
  -- This is because nginx doesn't resolve the /etc/hosts file but /etc/resolv.conf
  -- And it may cause errors like "host not found" for "localhost"
  self._properties.hosts = normalize_localhost(self._properties.hosts)

  self.apis = Apis(properties)
  self.consumers = Consumers(properties)
  self.plugins_configurations = PluginsConfigurations(properties)
  self.basicauth_credentials = BasicAuthCredentials(properties)
  self.ratelimiting_metrics = RateLimitingMetrics(properties)
  self.keyauth_credentials = KeyAuthCredentials(properties)
  self.datausage_metrics = DataUsageMetrics(properties)

  self.migrations = Migrations(properties)
end

function CassandraFactory:drop()
  return self:execute_queries [[
    TRUNCATE apis;
    TRUNCATE consumers;
    TRUNCATE plugins_configurations;
    TRUNCATE basicauth_credentials;
    TRUNCATE keyauth_credentials;
    TRUNCATE ratelimiting_metrics;
    TRUNCATE datausage_metrics;
  ]]
end

-- Prepare all statements of collections `._queries` property and put them
-- in a statements cache
--
-- Note:
-- Even if the BaseDAO's :_execute_kong_query() method support preparation of statements on-the-go,
-- this method should be called when Kong starts in order to detect any failure in advance
-- as well as test the connection to Cassandra.
--
-- @return error if any
function CassandraFactory:prepare()
  local function prepare_collection(collection, collection_queries)
    if not collection_queries then collection_queries = collection._queries end
    for stmt_name, collection_query in pairs(collection_queries) do
      if type(collection_query) == "table" and collection_query.query == nil then
        -- Nested queries, let's recurse to prepare them too
        prepare_collection(collection, collection_query)
      else
        local _, err = collection:prepare_kong_statement(collection_query)
        if err then
          error(err)
        end
      end
    end
  end

  for _, collection in ipairs({ self.apis,
                                self.consumers,
                                self.plugins_configurations,
                                self.ratelimiting_metrics,
                                self.basicauth_credentials,
                                self.keyauth_credentials,
                                self.datausage_metrics }) do
    local status, err = pcall(function() prepare_collection(collection) end)
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

return CassandraFactory
