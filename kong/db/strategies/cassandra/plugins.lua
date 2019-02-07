local cassandra = require "cassandra"
local split = require("pl.stringx").split

local workspaces = require "kong.workspaces"
local get_workspaces = workspaces.get_workspaces
local workspace_entities_map = workspaces.workspace_entities_map


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

  local ws_scope = get_workspaces()
  local ws_entities_map
  if ws_scope then
    ws_entities_map = workspace_entities_map(ws_scope, "plugins")
  end

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

            if ws_scope then
              local ws_entity = ws_entities_map[row.id]
              if ws_entity then
                row.workspace_id = ws_entity.workspace_id
                row.workspace_name = ws_entity.workspace_name
                return self:deserialize_row(row)
              end

              return nil
            end
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
