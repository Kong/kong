-- Copyright (C) Mashape, Inc.
local Object = require "classic"
local cassandra = require "cassandra"

local Faker = require "apenode.tools.faker"
local migrations = require "apenode.tools.migrations"

local Apis = require "apenode.dao.cassandra.apis"
local Metrics = require "apenode.dao.cassandra.metrics"
local Plugins = require "apenode.dao.cassandra.plugins"
local Accounts = require "apenode.dao.cassandra.accounts"
local Applications = require "apenode.dao.cassandra.applications"

local CassandraFactory = Object:extend()

-- Instanciate a Cassandra DAO.
-- @param properties Cassandra properties
function CassandraFactory:new(properties)
  self.type = "cassandra"
  -- Private
  self._properties = properties
  self._migrations = migrations(self, { keyspace = properties.keyspace })
  self._db = cassandra.new()
  self._db:connect(properties.host, properties.port)
  self._db:set_timeout(properties.timeout)

  -- Public

  -- TODO: do not include on production
  self.faker = Faker(self)


  self.apis = Apis(self._db)
  self.metrics = Metrics(self._db)
  self.plugins = Plugins(self._db)
  self.accounts = Accounts(self._db)
  self.applications = Applications(self._db)
end

--
-- Migrations
--
function CassandraFactory:migrate(callback)
  self._migrations:migrate(callback)
end

function CassandraFactory:rollback(callback)
  self._migrations:rollback(callback)
end

function CassandraFactory:reset(callback)
  self._migrations:reset(callback)
end

--
-- Seeding
--
function CassandraFactory:seed(random, number)
  self.faker:seed(random, number)
end

function CassandraFactory:drop()
  self:execute [[
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
  self._db:set_keyspace(self._properties.keyspace)

  self.apis:prepare()
  self.metrics:prepare()
  self.plugins:prepare()
  self.accounts:prepare()
  self.applications:prepare()
end

function CassandraFactory:execute(stmt, no_keyspace)
  local session = cassandra.new()
  session:set_timeout(self._properties.timeout)

  local connected, err = session:connect(self._properties.host, self._properties.port)
  if not connected then
    error(err)
  end

  if no_keyspace == nil then
    session:set_keyspace(self._properties.keyspace)
  end

  -- Cassandra client doesn't support batches,
  -- we must split commands to execute them individually.
  -- See: https://github.com/jbochi/lua-resty-cassandra/issues/26
  local queries = stringy.split(stmt, ";")
  for _,query in ipairs(queries) do
    if stringy.strip(query) ~= "" then
      local result, err = session:execute(query)
      if err then
        error("Cassandra execution error: "..err)
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
