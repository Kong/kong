local Migration = {
  name = "2015-01-12-175310_init_schema",

  up = [[
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
      period TEXT,
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
  ]],

  down = [[
    DROP TABLE apis;
    DROP TABLE metrics;
    DROP TABLE plugins;
    DROP TABLE accounts;
    DROP TABLE applications;
  ]]
}

return Migration
