-- Copyright (C) Mashape, Inc.
local Object = require "classic"

local Faker = require "apenode.dao.faker"
local Apis = require "apenode.dao.cassandra.apis"
local Metrics = require "apenode.dao.cassandra.metrics"
local Accounts = require "apenode.dao.cassandra.accounts"
local Applications = require "apenode.dao.cassandra.applications"
local Plugins = require "apenode.dao.cassandra.plugins"

local CassandraFactory = Object:extend()

function CassandraFactory:new(configuration)
  -- Build factory
  self.apis = Apis(configuration)
  self.metrics = Metrics(configuration)
  self.accounts = Accounts(configuration)
  self.applications = Applications(configuration)
  self.plugins = Plugins(configuration)
end

function CassandraFactory:create_schema()
  error("Cann't create Cassandra schema")
end

function CassandraFactory:populate(random, number)
  Faker.populate(self, random, number)
end

function CassandraFactory.fake_entity(type, invalid)
  return Faker.fake_entity(type, invalid)
end

function CassandraFactory:drop()
  error("Can't drop Cassandra")
end

return CassandraFactory
