local sqlite3 = require "lsqlite3"
local db = sqlite3.open_memory()

local function db_exec(stmt)
  if db:exec(stmt) ~= sqlite3.OK then
    print("SQLite ERROR: ", db:errmsg())
  end
end

-- Create schema
db_exec [[

  CREATE TABLE accounts (
    id	 INTEGER PRIMARY KEY,
    provider_id TEXT UNIQUE,
    created_at TIMESTAMP DEFAULT (strftime('%s', 'now'))
  );

  CREATE TABLE apis (
    id	 INTEGER PRIMARY KEY,
    name	 VARCHAR(50) UNIQUE,
    public_dns VARCHAR(50) UNIQUE,
    target_url VARCHAR(50),
    authentication_type VARCHAR(10),
    created_at TIMESTAMP DEFAULT (strftime('%s', 'now'))
  );

  CREATE TABLE applications (
    id INTEGER PRIMARY KEY,
    account_id INTEGER,
    public_key TEXT,
    secret_key TEXT,
    created_at TIMESTAMP DEFAULT (strftime('%s', 'now')),
    FOREIGN KEY(account_id) REFERENCES accounts(id)
  );

]]

-- Build factory
local Apis = require "apenode.dao.sqlite.apis"
local Accounts = require "apenode.dao.sqlite.accounts"
local Applications = require "apenode.dao.sqlite.applications"

local _M = {
  _db = db,
  apis = Apis(db),
  accounts = Accounts(db),
  applications = Applications(db)
}

function _M.populate()
  -- Build insert APIs
  local insert_apis_stmt = ""
  for i = 1, 1000 do
    insert_apis_stmt = insert_apis_stmt .. [[
      INSERT INTO apis(name, public_dns, target_url, authentication_type)
        VALUES("httpbin]]..i..[[",
               "apebin]]..i..[[.com",
               "http://httpbin.org/",
               "query");
    ]]
  end

  -- Build insert Accounts
  local insert_accounts_stmt = ""
  for i = 1, 1000 do
    insert_accounts_stmt = insert_accounts_stmt .. [[
      INSERT INTO accounts(provider_id) VALUES("provider]]..i..[[");
    ]]
  end

  -- Build insert applications
  local insert_applications_stmt = ""
  for i = 1, 1000 do
    insert_applications_stmt = insert_applications_stmt .. [[
      INSERT INTO applications(account_id, public_key, secret_key)
        VALUES("1",
               "public_key",
               "cazzo");
    ]]
  end

  db_exec(insert_apis_stmt)
  db_exec(insert_accounts_stmt)
  db_exec(insert_applications_stmt)
end

function _M.drop()
  db_exec("DELETE FROM apis")
  db_exec("DELETE FROM accounts")
  db_exec("DELETE FROM applications")
end

return _M