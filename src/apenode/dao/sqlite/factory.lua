-- Copyright (C) Mashape, Inc.
local Object = require "classic"
local sqlite3 = require "lsqlite3"
local Faker = require "apenode.dao.faker"
local Apis = require "apenode.dao.sqlite.apis"
local Metrics = require "apenode.dao.sqlite.metrics"
local Plugins = require "apenode.dao.sqlite.plugins"
local Accounts = require "apenode.dao.sqlite.accounts"
local Applications = require "apenode.dao.sqlite.applications"

local SQLiteFactory = Object:extend()

-- Instanciate an SQLite DAO.
-- @param properties The parsed apenode configuration
-- @param db_only Only instanciate the BD connection if true, doesn't prepare statements
--                very probably because the tables don't exist yet.
function SQLiteFactory:new(properties, db_only)
  if properties.memory then
    self._db = sqlite3.open_memory()
  elseif properties.file_path ~= nil then
    self._db = sqlite3.open(properties.file_path)
  else
    error("Cannot open SQLite database: missing path to file")
  end

  self.db_only = db_only

  -- Build factory
  if not db_only then
    self.apis = Apis(self._db)
    self.metrics = Metrics(self._db)
    self.plugins = Plugins(self._db)
    self.accounts = Accounts(self._db)
    self.applications = Applications(self._db)
  end
end

function SQLiteFactory:execute(stmt)
  if self._db:exec(stmt) ~= sqlite3.OK then
    error("SQLite ERROR: "..self._db:errmsg())
  end
end

function SQLiteFactory:populate(random, number)
  Faker.populate(self, random, number)
end

function SQLiteFactory.fake_entity(type, invalid)
  return Faker.fake_entity(type, invalid)
end

function SQLiteFactory:drop()
  self:execute("DELETE FROM apis")
  self:execute("DELETE FROM metrics")
  self:execute("DELETE FROM plugins")
  self:execute("DELETE FROM accounts")
  self:execute("DELETE FROM applications")
end

function SQLiteFactory:close()
  if not self.db_only then
    self.apis:finalize()
    self.metrics:finalize()
    self.plugins:finalize()
    self.accounts:finalize()
    self.applications:finalize()
  end

  self._db:close()
end

return SQLiteFactory
