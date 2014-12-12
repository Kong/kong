local sqlite3 = require "lsqlite3"
local db

if configuration.dao.properties.memory then
  db = sqlite3.open_memory()
elseif configuration.dao.properties.file_path ~= nil then
  db = sqlite3.open(configuration.dao.properties.file_path)
else
  ngx.log(ngx.ERR, "cannot open sqlite database")
  return
end

math.randomseed(os.time())

local function db_exec(stmt)
  if db:exec(stmt) ~= sqlite3.OK then
    print("SQLite ERROR: ", db:errmsg())
  end
end

-- Create schema
db_exec [[

  CREATE TABLE IF NOT EXISTS accounts (
    id	 INTEGER PRIMARY KEY,
    provider_id TEXT UNIQUE,
    created_at TIMESTAMP DEFAULT (strftime('%s', 'now'))
  );

  CREATE TABLE IF NOT EXISTS apis (
    id	 INTEGER PRIMARY KEY,
    name	 VARCHAR(50) UNIQUE,
    public_dns VARCHAR(50) UNIQUE,
    target_url VARCHAR(50),
    authentication_type VARCHAR(10),
    authentication_key_names VARCHAR(50),
    created_at TIMESTAMP DEFAULT (strftime('%s', 'now'))
  );

  CREATE TABLE IF NOT EXISTS applications (
    id INTEGER PRIMARY KEY,
    account_id INTEGER,
    public_key TEXT,
    secret_key TEXT,
    created_at TIMESTAMP DEFAULT (strftime('%s', 'now')),

    FOREIGN KEY(account_id) REFERENCES accounts(id)
  );

  CREATE TABLE IF NOT EXISTS metrics (
    id INTEGER PRIMARY KEY,
    api_id INTEGER,
    account_id INTEGER,
    name TEXT,
    value INTEGER,
    timestamp TEXT,

    FOREIGN KEY(account_id) REFERENCES accounts(id),
    FOREIGN KEY(api_id) REFERENCES apis(id)
  );

]]

-- Build factory
local Apis = require "apenode.dao.sqlite.apis"
local Accounts = require "apenode.dao.sqlite.accounts"
local Applications = require "apenode.dao.sqlite.applications"
local Metrics = require "apenode.dao.sqlite.metrics"

local _M = {
  _db = db,
  apis = Apis(db),
  accounts = Accounts(db),
  applications = Applications(db),
  metrics = Metrics(db)
}

function _M.fake_entity(type, invalid)
  local r = math.random(1, 10000000)

  if type == "ApisDao" then
    local name
    if invalid then name = "httpbin1" else name = "random"..r end
    return {
      name = name,
      public_dns = "random"..r..".com",
      target_url = "http://random"..r..".com",
      authentication_type = "query",
      authentication_key_names = {
        "X-Mashape-Key",
        "X-Apenode-Key"
      }
    }
  elseif type == "AccountsDao" then
    local provider_id
    if invalid then provider_id = "provider1" else provider_id = "random_provider_id_"..r end
    return {
      provider_id = provider_id
    }
  elseif type == "ApplicationsDao" then
    return {
      account_id = 1,
      public_key = "random"..r,
      secret_key = "random"..r,
    }
  elseif type == "MetricsDao" then
    return {
      api_id = 1,
      account_id = 1,
      name = "requests",
      value = r,
      timestamp = 123
    }
  end
end

function _M.populate(real)
  local insert_apis_stmt = ""
  local insert_accounts_stmt = ""
  local insert_applications_stmt = ""
  local insert_metrics_stmt = ""

  if not real then
    -- Build insert APIs
    for i = 1, 1000 do
      insert_apis_stmt = insert_apis_stmt .. [[
        INSERT INTO apis(name, public_dns, target_url, authentication_type, authentication_key_names)
          VALUES("httpbin]]..i..[[",
                 "apebin]]..i..[[.com",
                 "http://httpbin.org/",
                 "query",
                 "X-Apenode-Key;X-Mashape-Key");
      ]]
    end
    -- Build insert Accounts
    for i = 1, 1000 do
      insert_accounts_stmt = insert_accounts_stmt .. [[
        INSERT INTO accounts(provider_id) VALUES("provider]]..i..[[");
      ]]
    end
    -- Build insert applications
    for i = 1, 1000 do
      insert_applications_stmt = insert_applications_stmt .. [[
        INSERT INTO applications(account_id, public_key, secret_key)
          VALUES("1",
                 "public_key",
                 "cazzo");
      ]]
    end
    -- Build insert metrics
    for i = 1, 1000 do
      insert_metrics_stmt = insert_metrics_stmt .. [[
        INSERT INTO metrics(api_id, account_id, name, value, timestamp)
          VALUES(1,
                 1,
                 "requests",
                 256,
                 NULL);
      ]]
    end
  else
    insert_apis_stmt = insert_apis_stmt .. [[
      INSERT INTO apis(name, public_dns, target_url, authentication_type)
        VALUES("test", "test.com", "http://httpbin.org", "query");
    ]]

    insert_apis_stmt = insert_apis_stmt .. [[
      INSERT INTO apis(name, public_dns, target_url, authentication_type)
        VALUES("test2", "test2.com", "http://httpbin.org", "header");
    ]]

    insert_apis_stmt = insert_apis_stmt .. [[
      INSERT INTO apis(name, public_dns, target_url, authentication_type)
        VALUES("test3", "test3.com", "http://httpbin.org", "basic");
    ]]

    insert_accounts_stmt = insert_accounts_stmt .. [[
      INSERT INTO accounts(provider_id) VALUES("provider_123");
    ]]

    insert_applications_stmt = insert_applications_stmt .. [[
      INSERT INTO applications(account_id, public_key, secret_key)
        VALUES("1",
               NULL,
               "apikey123");
    ]]

    insert_applications_stmt = insert_applications_stmt .. [[
      INSERT INTO applications(account_id, public_key, secret_key)
        VALUES("1",
               "user123",
               "apikey123");
    ]]
  end

  db_exec(insert_apis_stmt)
  db_exec(insert_accounts_stmt)
  db_exec(insert_applications_stmt)
  db_exec(insert_metrics_stmt)
end

function _M.drop()
  db_exec("DELETE FROM apis")
  db_exec("DELETE FROM accounts")
  db_exec("DELETE FROM applications")
  db_exec("DELETE FROM metrics")
end

return _M
