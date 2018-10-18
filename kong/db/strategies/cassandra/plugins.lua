local cassandra = require "cassandra"
local split = require("pl.stringx").split
local cjson = require("cjson")


local insert = table.insert
local fmt = string.format


local Plugins = {}


-- Emulate the `select_by_cache_key` operation
-- using the `plugins` table of a 0.14 database.
-- @tparam string key a 0.15+ plugin cache_key
-- @treturn table|nil,err the row for this unique cache_key
-- or nil and an error object.
function Plugins:select_by_cache_key_migrating(key)
  -- unpack cache_key
  local parts = split(key, ":")

  -- build query and args
  local qbuild = { "SELECT * FROM %s WHERE name = ?" }
  local args = { cassandra.text(parts[2]) }
  for i, field in ipairs({
    "route_id",
    "service_id",
    "consumer_id",
    "api_id",
  }) do
    local id = parts[i + 2]
    if id ~= "" then
      insert(qbuild, field .. " = ?")
      insert(args, cassandra.uuid(id))
    else
      parts[i + 2] = nil
    end
  end
  local query = table.concat(qbuild, " AND ") .. " ALLOW FILTERING"

  -- perform query, trying both temp and old table
  local errs = 0
  local last_err
  for _, tbl in ipairs({ "plugins_temp", "plugins" }) do
    for rows, err in self.connector.cluster:iterate(fmt(query, tbl), args) do
      if err then
        -- some errors here may happen depending of migration stage
        errs = errs + 1
        last_err = err
        break
      end

      for i = 1, #rows do
        local row = rows[i]
        if row then
          if row.route_id == parts[3] and
             row.service_id == parts[4] and
             row.consumer_id == parts[5] and
             row.api_id == parts[6] then
            row.config = cjson.decode(row.config)
            row.cache_key = nil
            return row
          end
        end
      end
    end
  end

  -- not found
  return nil, errs == 2 and last_err
end


return Plugins
