local sqlite = require "lsqlite3"
local db = sqlite.open_memory()



assert(db:exec[[
  CREATE TABLE apis (
    id	 INTEGER PRIMARY KEY,
    name	 VARCHAR(50),
    public_dns VARCHAR(50),
    target_url VARCHAR(50),
    authentication_type VARCHAR(10)
  );

  INSERT INTO apis(name, public_dns, target_url, authentication_type) VALUES("httpbin", "apebin.com", "http://httpbin.org/", "query");
]])

function all_apis()
  return db:nrows("SELECT * FROM apis")
end

for api_row in all_apis() do
  print(api_row.id, api_row.name, api_row.public_dns, api_row.target_url)
end

db:close()