-- Copyright (C) Mashape, Inc.
local sqlite3 = require "lsqlite3"
local Object = require "classic"

local Faker = require "apenode.dao.faker"
local Apis = require "apenode.dao.sqlite.apis"
local Metrics = require "apenode.dao.sqlite.metrics"
local Accounts = require "apenode.dao.sqlite.accounts"
local Applications = require "apenode.dao.sqlite.applications"
local Plugins = require "apenode.dao.sqlite.plugins"

local SQLiteFactory = Object:extend()

-- Instanciates an SQLite DAO.
-- @param configuration The SQLite configuration from apenode's config
-- @param db_only Only instanciate the BD connection if true, doesn't initialize statements
function SQLiteFactory:new(configuration, db_only)
  if configuration.memory then
    self._db = sqlite3.open_memory()
  elseif configuration.file_path ~= nil then
    self._db = sqlite3.open(configuration.file_path)
  else
    error("Cannot open SQLite database")
  end

  self.db_only = db_only

  -- Build factory
  if not db_only then
    self.apis = Apis(self._db)
    self.metrics = Metrics(self._db)
    self.accounts = Accounts(self._db)
    self.applications = Applications(self._db)
    self.plugins = Plugins(self._db)
  end
end

function SQLiteFactory:execute(stmt)
  if self._db:exec(stmt) ~= sqlite3.OK then
    error("SQLite ERROR: ", self._db:errmsg())
  end
end

function SQLiteFactory:populate(random, number)
  Faker.populate(self, random, number)
end

function SQLiteFactory.fake_entity(type, invalid)
  return Faker.fake_entity(type, invalid)
end

function SQLiteFactory:drop()
  self:db_exec("DELETE FROM apis")
  self:db_exec("DELETE FROM accounts")
  self:db_exec("DELETE FROM applications")
  self:db_exec("DELETE FROM metrics")
  self:db_exec("DELETE FROM plugins")
end

function SQLiteFactory:close()
  if not self.db_only then
    self.apis:finalize()
    self.metrics:finalize()
    self.accounts:finalize()
    self.applications:finalize()
    self.plugins:finalize()
  end

  self._db:close()
end

return SQLiteFactory
