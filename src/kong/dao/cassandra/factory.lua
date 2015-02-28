-- Copyright (C) Mashape, Inc.
local Object = require "classic"
local cassandra = require "cassandra"
local stringy = require "stringy"

local Faker = require "kong.tools.faker"
local migrations = require "kong.tools.migrations"

local Apis = require "kong.dao.cassandra.apis"
local Metrics = require "kong.dao.cassandra.metrics"
local Plugins = require "kong.dao.cassandra.plugins"
local Accounts = require "kong.dao.cassandra.accounts"
local Applications = require "kong.dao.cassandra.applications"

local CassandraFactory = Object:extend()

-- Instanciate a Cassandra DAO.
-- @param properties Cassandra properties
function CassandraFactory:new(properties)
  self.type = "cassandra"
  self._properties = properties

  self.apis = Apis(properties)
  self.metrics = Metrics(properties)
  self.plugins = Plugins(properties)
  self.accounts = Accounts(properties)
  self.applications = Applications(properties)
end

function CassandraFactory:drop()
  return self:execute [[
    TRUNCATE apis;
    TRUNCATE metrics;
    TRUNCATE plugins;
    TRUNCATE accounts;
    TRUNCATE applications;
  ]]
end

-- Prepare all statements in collection._queries and put them in collection._statements.
-- Should be called with only a collection and will recursively call itself for nested statements.
--
-- @param collection A collection with a ._queries property
local function prepare(collection, queries, statements)
  if not queries then queries = collection._queries end
  if not statements then statements = collection._statements end

  for stmt_name, query in pairs(queries) do
    if type(query) == "table" and query.query == nil then
      collection._statements[stmt_name] = {}
      prepare(collection, query, collection._statements[stmt_name])
    else
      local q = stringy.strip(query.query)
      q = string.format(q, "")
      local kong_stmt, err = collection:prepare_kong_statement(q, query.params)
      if err then
        return err
      end
      statements[stmt_name] = kong_stmt
    end
  end
end

-- Prepare all statements of collections
-- @return error if any
function CassandraFactory:prepare()
  for _, collection in ipairs({ self.apis,
                                self.metrics,
                                self.plugins,
                                self.accounts,
                                self.applications }) do
    local err = prepare(collection)
    if err then
      return err
    end
  end
end

-- Execute a string of queries separated by ;
-- Useful for huge DDL operations such as migrations
--
-- @param {string} queries Semicolon separated string of queries
-- @param {boolean} no_keyspace Won't set the keyspace if true
-- @return {string} error if any
function CassandraFactory:execute(queries, no_keyspace)
  local ok, err

  local session = cassandra.new()
  session:set_timeout(self._properties.timeout)

  ok, err = session:connect(self._properties.hosts, self._properties.port)
  if not ok then
    return err
  end

  if no_keyspace == nil then
    ok, err = session:set_keyspace(self._properties.keyspace)
    if not ok then
      return err
    end
  end

  -- Cassandra only supports BATCH on DML statements.
  -- We must split commands to execute them individually for migrations and such
  queries = stringy.split(queries, ";")
  for _, query in ipairs(queries) do
    if stringy.strip(query) ~= "" then
      local _, stmt_err = session:execute(query)
      if stmt_err then
        return stmt_err
      end
    end
  end

  session:close()
end

return CassandraFactory
