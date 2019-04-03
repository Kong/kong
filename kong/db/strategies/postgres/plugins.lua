local split = require("pl.stringx").split

local ok, new_tab = pcall(require, "table.new")
if not ok then
  new_tab = function (narr, nrec) return {} end
end


local insert = table.insert
local concat = table.concat


local Plugins = {}


-- Given several cache_keys, return all the plugins that match them, in the same order as the provided keys
function Plugins:select_by_cache_keys(keys)
  local len = #keys
  local escaped_keys = new_tab(len, 0)
  local order_by_cases = new_tab(len, 0)
  local key, escaped
  for i = 1, len do
    key = keys[i]
    escaped = self:escape_literal(key)
    escaped_keys[i] = escaped
    order_by_cases[i] = "WHEN " .. escaped  .. " THEN " .. tostring(i)
  end

  local query = "SELECT " ..
                self.statements.select.expr ..
                " FROM plugins WHERE cache_key IN (" ..
                concat(escaped_keys, ", ") ..
                ") ORDER BY CASE cache_key " ..
                concat(order_by_cases, "\n") ..
                "\n END"
  local plugins, err = self.connector:query(query)
  if not plugins then
    return nil, err
  end

  len = #plugins
  local expanded = new_tab(len, 0)
  local expand = self.expand
  for i = 1, len do
    plugins[i].cache_key = nil
    expanded[i] = expand(plugins[i])
  end
  return expanded
end


-- Emulate the `select_by_cache_key` operation
-- using the `plugins` table of a 0.14 database.
-- @tparam string key a 0.15+ plugin cache_key
-- @treturn table|nil,err the row for this unique cache_key
-- or nil and an error object.
function Plugins:select_by_cache_key_migrating(key)
  -- unpack cache_key
  local parts = split(key, ":")
  -- build query and args

  local qbuild = { "SELECT " ..
                   self.statements.select.expr ..
                   " FROM plugins WHERE name = " ..
                   self:escape_literal(parts[2]) }
  for i, field in ipairs({
    "route_id",
    "service_id",
    "consumer_id",
    "api_id",
  }) do
    local id = parts[i + 2]
    if id ~= "" then
      insert(qbuild, field .. " = '" .. id .. "'")
    else
      insert(qbuild, field .. " IS NULL")
    end
  end
  local query = table.concat(qbuild, " AND ")

  -- perform query
  local res, err = self.connector:query(query)
  if res and res[1] then
    res[1].cache_key = nil
    return self.expand(res[1]), nil
  end

  -- not found
  return nil, err
end


return Plugins
