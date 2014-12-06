local sqlite3 = require "lsqlite3"
local db = sqlite3.open_memory()

-- Apenode DAOs
local Apis = require "apenode.dao.sqlite.apis"

function db_exec(stmt)
  if db:exec(stmt) ~= sqlite3.OK then
    print("Sqlite ERROR:        ", db:errmsg())
  end
end

db_exec[[
  CREATE TABLE apis (
    id	 INTEGER PRIMARY KEY,
    name	 VARCHAR(50),
    public_dns VARCHAR(50),
    target_url VARCHAR(50),
    authentication_type VARCHAR(10)
  );
]]

local _M = {
  _db = db,
  apis = Apis(db)
}

function _M.populate()
  db_exec[[
    INSERT INTO apis(name, public_dns, target_url, authentication_type) VALUES("httpbin", "apebin.com", "http://httpbin.org/", "query");
  ]]
end

return _M