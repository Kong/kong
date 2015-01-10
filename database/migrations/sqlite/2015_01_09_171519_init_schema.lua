-- Inserted variables
local Object = require "classic"
local dao_factory = require "apenode.dao.sqlite"


-- Migration interface
local Migration = Object:extend()

function Migration:new(dao_configuration)
  self.dao = dao_factory(dao_configuration.properties, true)
end

function Migration:up()
  self.dao:execute [[

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

    CREATE TABLE IF NOT EXISTS plugins(
      id INTEGER PRIMARY KEY,
      api_id INTEGER,
      application_id INTEGER,
      name TEXT,
      value TEXT,
      created_at TIMESTAMP,

      FOREIGN KEY(api_id) REFERENCES apis(id), FOREIGN KEY(application_id) REFERENCES applications(id)
    );

  ]]

  self.dao:close()
end

function Migration:down()
  self.dao:execute [[

  ]]

  self.dao:close()
end

return Migration
