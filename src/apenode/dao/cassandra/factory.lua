-- Copyright (C) Mashape, Inc.
local Object = require "classic"
local cassandra = require "cassandra"

local Faker = require "apenode.tools.faker"
local Migrations = require "apenode.tools.migrations"

local Apis = require "apenode.dao.cassandra.apis"
local Metrics = require "apenode.dao.cassandra.metrics"
local Plugins = require "apenode.dao.cassandra.plugins"
local Accounts = require "apenode.dao.cassandra.accounts"
local Applications = require "apenode.dao.cassandra.applications"

local CassandraFactory = Object:extend()

-- Instanciate an SQLite DAO.
-- @param properties The parsed apenode configuration
function CassandraFactory:new(properties)
  self.type = "cassandra"
  self.faker = Faker(self)
  self.migrations = Migrations(self)
  self._properties = properties

  self._db = cassandra.new()
  self._db:connect(properties.host, properties.port)
  self._db:set_keyspace(properties.keyspace)
  self._db:set_timeout(properties.timeout)

  self.apis = Apis(self._db)
  --self.metrics = Metrics(self._db, properties)
  --self.plugins = Plugins(self._db, properties)
  self.accounts = Accounts(self._db)
  self.applications = Applications(self._db, properties)
end

--
-- Migrations
--
function CassandraFactory:migrate(callback)
  self.migrations:migrate(callback)
end

function CassandraFactory:rollback(callback)
  self.migrations:rollback(callback)
end

function CassandraFactory:reset(callback)
  self.migrations:reset(callback)
end

--
-- Seeding
--
function CassandraFactory:seed(random, number)
  self.faker:seed(random, number)
end

function CassandraFactory:drop()
  self:execute [[
    USE apenode;
    TRUNCATE apis;
    TRUNCATE metrics;
    TRUNCATE plugins;
    TRUNCATE accounts;
    TRUNCATE applications;
  ]]
end

--
-- Utilities
--
function CassandraFactory:prepare()
  self.apis:prepare()
  self.accounts:prepare()
  self.applications:prepare()
end

function CassandraFactory:execute(stmt)
  session = cassandra.new()
  session:set_timeout(self._properties.timeout)
  local connected, err = session:connect(self._properties.host, self._properties.port)
  if not connected then
    error(err)
  end

  --session:set_keyspace(self._properties.keyspace)

  -- Cassandra client doesn't support batches, splitting commands
  -- https://github.com/jbochi/lua-resty-cassandra/issues/26
  local queries = stringy.split(stmt, ";")
  for _,query in ipairs(queries) do
    if stringy.strip(query) ~= "" then
      local result, err = session:execute(query)
      if err then
        error(err)
      end
    end
  end
end

function CassandraFactory:close()
  local ok, err = self._db:close()
  if err then
    error("Cannot close Cassandra session: "..err)
  end
end

return CassandraFactory
