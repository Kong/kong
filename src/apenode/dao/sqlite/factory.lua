local sqlite3 = require "lsqlite3"
local db = sqlite3.open_memory()

function db_exec(stmt)
  if db:exec(stmt) ~= sqlite3.OK then
    print("SQLite ERROR: ", db:errmsg())
  end
end

-- Create schema
db_exec[[

  CREATE TABLE apis (
    id	 INTEGER PRIMARY KEY,
    name	 VARCHAR(50) UNIQUE,
    public_dns VARCHAR(50) UNIQUE,
    target_url VARCHAR(50),
    authentication_type VARCHAR(10)
  );

]]

-- Build factory
local Apis = require "apenode.dao.sqlite.apis"

local _M = {
  _db = db,
  apis = Apis(db)
}

function _M.populate()
  -- Build insert APIs
  local insert_apis_stmt = ""
  for i = 1, 100 do
    insert_apis_stmt = insert_apis_stmt .. [[
    INSERT INTO apis(name, public_dns, target_url, authentication_type)
        VALUES("httpbin]]..i..[[",
          "apebin]]..i..[[.com",
          "http://httpbin.org/",
          "query");
    ]]
  end

  db_exec(insert_apis_stmt)
end

return _M