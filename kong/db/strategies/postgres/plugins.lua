local split = require("pl.stringx").split
local ws_scope_as_list = require("kong.workspaces.helper").ws_scope_as_list


local insert = table.insert


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
  local qbuild = { "SELECT " ..
                   self.statements.select.expr ..
                   " FROM plugins WHERE name = " ..
                   self:escape_literal(parts[2]) }

  local ws_list = ws_scope_as_list("plugins")
  if ws_list then
    qbuild = { "SELECT " .. self.statements.select.expr .. ", \"workspace_id\", \"workspace_name\"" ..
               " FROM workspace_entities ws_e INNER JOIN plugins plugins" ..
               " ON ( unique_field_name = 'id' AND ws_e.workspace_id in (" ..
               ws_scope_as_list("plugins") .. ") and ws_e.entity_id = plugins.id::varchar )" ..
               " WHERE plugins.name = " .. self:escape_literal(parts[2]) }
  end
  for i, field in ipairs({
    "route_id",
    "service_id",
    "consumer_id",
    "api_id",
  }) do
    local id = parts[i + 2]
    if id ~= "" then
      insert(qbuild, "plugins." .. field .. " = '" .. id .. "'")
    else
      insert(qbuild, "plugins." .. field .. " IS NULL")
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
