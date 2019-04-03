local cassandra = require "cassandra"
local split = require("pl.stringx").split

local ok, new_tab = pcall(require, "table.new")
if not ok then
  new_tab = function (narr, nrec) return {} end
end

local insert = table.insert
local fmt = string.format


local Plugins = {}


-- Given several cache_keys, return all the plugins that match them, in the same order as the provided keys
-- Cassandra currently doesn't seem to support IN for non-primary-keys
-- https://issues.apache.org/jira/browse/CASSANDRA-6318 <- marked as "resolved", but the problem is not fixed
-- So what this method does is several requests, one per key
function Plugins:select_by_cache_keys(keys)
  local keys_len = #keys
  local plugins = new_tab(keys_len, 0)
  local plugins_len = 0

  local connector = self.connector
  local deserialize_row = self.deserialize_row
  local do_query = connector.query
  local cassandra_text = cassandra.text
  local rows, row, err

  connector:connect() -- do all the requests against the same node  & save some handshake time
  for i = 1, keys_len do
    rows, err = do_query(connector,
                         "SELECT * FROM plugins WHERE cache_key = ?",
                         { cassandra_text(keys[i]) })
    if not rows then
      return nil, err
    end

    row = rows[1]

    if row then
      plugins_len = plugins_len + 1
      plugins[plugins_len] = deserialize_row(self, row)
    end
  end

  return plugins
end


-- Emulate the `select_by_cache_key` operation
-- using the `plugins` table of a 0.14 database.
-- @tparam string key a 0.15+ plugin cache_key
-- @treturn table|nil,err the row for this unique cache_key
-- or nil and an error object.
function Plugins:select_by_cache_key_migrating(key)
  -- unpack cache_key
  local parts = split(key, ":")

  local c3 = self.connector.major_version >= 3

  -- build query and args
  local qbuild = {}
  local args = {}
  for i, field in ipairs({
    "route_id",
    "service_id",
    "consumer_id",
    "api_id",
  }) do
    local id = parts[i + 2]
    if id ~= "" then
      if c3 or #args == 0 then
        insert(qbuild, field .. " = ?")
        insert(args, cassandra.uuid(id))
      end
    else
      parts[i + 2] = nil
    end
  end
  if c3 or #args == 0 then
    insert(qbuild, "name = ?")
    insert(args, cassandra.text(parts[2]))
  end
  local query = "SELECT * FROM %s WHERE " ..
                table.concat(qbuild, " AND ") ..
                " ALLOW FILTERING"

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
          if row.name == parts[2] and
             row.route_id == parts[3] and
             row.service_id == parts[4] and
             row.consumer_id == parts[5] and
             row.api_id == parts[6] then
            row.cache_key = nil
            return self:deserialize_row(row)
          end
        end
      end
    end
  end

  -- not found
  return nil, errs == 2 and last_err
end


return Plugins
