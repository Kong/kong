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

]]

-- Build factory
local Apis = require "apenode.dao.sqlite.apis"
local Accounts = require "apenode.dao.sqlite.accounts"


local _M = {
  _db = db,
  apis = Apis(db),
  accounts = Accounts(db)
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
  for j = 1, 1000 do
    insert_accounts_stmt = insert_accounts_stmt .. [[
      INSERT INTO accounts(provider_id) VALUES("provider]]..j..[[");
    ]]
  end

  db_exec(insert_apis_stmt)
  db_exec(insert_accounts_stmt)
end

return _M