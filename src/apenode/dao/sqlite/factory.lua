-- Copyright (C) Mashape, Inc.
local sqlite3 = require "lsqlite3"

local Faker = require "apenode.dao.faker"
local Apis = require "apenode.dao.sqlite.apis"
local Metrics = require "apenode.dao.sqlite.metrics"
local Accounts = require "apenode.dao.sqlite.accounts"
local Applications = require "apenode.dao.sqlite.applications"

local SQLiteFactory = {}
SQLiteFactory.__index = SQLiteFactory

setmetatable(SQLiteFactory, {
  __call = function (cls, ...)
    local self = setmetatable({}, cls)
    self:_init(...)
    return self
  end
})

function SQLiteFactory:_init(configuration)
  if configuration.memory then
    self._db = sqlite3.open_memory()
  elseif configuration.file_path ~= nil then
    self._db = sqlite3.open(configuration.file_path)
  else
    error("Cannot open SQLite database")
  end

  self:create_schema()

  -- Build factory
  self.apis = Apis(self._db)
  self.metrics = Metrics(self._db)
  self.accounts = Accounts(self._db)
  self.applications = Applications(self._db)
end

function SQLiteFactory:db_exec(stmt)
  if self._db:exec(stmt) ~= sqlite3.OK then
    error("SQLite ERROR: ", self._db:errmsg())
  end
end

function SQLiteFactory:create_schema()
  self:db_exec [[

    CREATE TABLE IF NOT EXISTS accounts(
      id INTEGER PRIMARY KEY,
      provider_id TEXT UNIQUE,
      created_at TIMESTAMP
    );

    CREATE TABLE IF NOT EXISTS apis(
      id INTEGER PRIMARY KEY,
      name VARCHAR(50) UNIQUE,
      public_dns VARCHAR(50) UNIQUE,
      target_url VARCHAR(50),
      authentication_type VARCHAR(10),
      authentication_key_names VARCHAR(50),
      created_at TIMESTAMP
    );

    CREATE TABLE IF NOT EXISTS applications(
      id INTEGER PRIMARY KEY,
      account_id INTEGER,
      public_key TEXT,
      secret_key TEXT,
      created_at TIMESTAMP,

      FOREIGN KEY(account_id) REFERENCES accounts(id)
    );

    CREATE TABLE IF NOT EXISTS metrics(
      api_id INTEGER NOT NULL,
      application_id INTEGER NOT NULL,
      name TEXT,
      timestamp INTEGER,
      value INTEGER,

      FOREIGN KEY(application_id) REFERENCES applications(id),
      FOREIGN KEY(api_id) REFERENCES apis(id),
      PRIMARY KEY(api_id, application_id, name)
    );

  ]]
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
end

function SQLiteFactory:close()
  self._db:close()
end

return SQLiteFactory
