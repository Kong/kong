-- Copyright (C) Mashape, Inc.
local Object = require "classic"

local Faker = require "apenode.tools.faker"
local Migrations = require "apenode.tools.migrations"
local Apis = require "apenode.dao.cassandra.apis"
local Metrics = require "apenode.dao.cassandra.metrics"
local Plugins = require "apenode.dao.cassandra.plugins"
local Accounts = require "apenode.dao.cassandra.accounts"
local Applications = require "apenode.dao.cassandra.applications"
local Client = require "apenode.dao.cassandra.client"

local CassandraFactory = Object:extend()

-- Instanciate an SQLite DAO.
-- @param properties The parsed apenode configuration
function CassandraFactory:new(properties)
  self.type = "cassandra"
  self.migrations = Migrations(self)

  -- Initialize client
  self._client = Client(properties)

  self.apis = Apis(self._client)
  self.metrics = Metrics(self._client)
  self.plugins = Plugins(self._client)
  self.accounts = Accounts(self._client)
  self.applications = Applications(self._client)
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
  Faker.seed(self, random, number)
end

function CassandraFactory.fake_entity(type, invalid)
  return Faker.fake_entity(type, invalid)
end

function CassandraFactory:drop()
  --TODO
end

--
-- Utilities
--
function CassandraFactory:prepare()

end

function CassandraFactory:execute(stmt)
  self._client:query(stmt, nil, true)
end

function CassandraFactory:close()
  self.apis:finalize()
  self.metrics:finalize()
  self.plugins:finalize()
  self.accounts:finalize()
  self.applications:finalize()
end

return CassandraFactory
