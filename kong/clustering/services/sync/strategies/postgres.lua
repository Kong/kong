local _M = {}
local _MT = { __index = _M }


local cjson = require("cjson.safe")


local string_format = string.format
local table_concat = table.concat
local cjson_encode = cjson.encode


function _M.new(db)
  local self = {
    connector = db.connector,
  }

  return setmetatable(self, _MT)
end


local NEW_VERSION_QUERY = [[
  DO $$
  DECLARE
    new_version integer;

  BEGIN
    INSERT INTO clustering_sync_version DEFAULT VALUES RETURNING version INTO new_version;
    INSERT INTO clustering_sync_delta (version, type, id, ws_id, row) VALUES %s;
  END $$;
]]


-- deltas: {
--   { type = "service", "id" = "d78eb00f-8702-4d6a-bfd9-e005f904ae3e", "ws_id" = "73478cf6-964f-412d-b1c4-8ac88d9e85e9", row = "JSON", }
--   { type = "route", "id" = "0a5bac5c-b795-4981-95d2-919ba3390b7e", "ws_id" = "73478cf6-964f-412d-b1c4-8ac88d9e85e9", row = "JSON", }
-- }
function _M:insert_delta(deltas)
  local delta_str = {}
  for i, d in ipairs(deltas) do
    delta_str[i] = string_format("(new_version, %s, %s, %s, %s)",
                                 self.connector:escape_literal(d.type),
                                 self.connector:escape_literal(d.id),
                                 self.connector:escape_literal(d.ws_id),
                                 self.connector:escape_literal(cjson_encode(d.row)))
  end

  local sql = string_format(NEW_VERSION_QUERY, table_concat(delta_str))

  return self.connector:query(sql)
end


function _M:get_delta(version)
  local sql = "SELECT * FROM clustering_sync_delta WHERE version > " .. self.connector:escape_literal(version) .. " ORDER BY version ASC"
  return self.connector:query(sql)
end


return _M
