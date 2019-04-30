local cassandra = require "cassandra"
local split = require("pl.stringx").split

local workspaces = require "kong.workspaces"
local get_workspaces = workspaces.get_workspaces
local workspace_entities_map = workspaces.workspace_entities_map


local insert = table.insert
local fmt = string.format


local Plugins = {}


function Plugins:select_by_field(field, value)
  local plugin, err = self.super.select_by_field(self, field, value)
  if err then
    return nil, err
  end

  -- the plugin was fetched with a cache key (that doesn't take
  -- workspaces into consideration); so we need to fetch the workspace(s)
  -- the plugin belongs to, in order to make sure it can be used for the
  -- current request's route workspaces
  --
  local found

  if plugin then
    local plugin_workspaces = kong.db.workspace_entities:select_all {
      entity_id = plugin.id,
      unique_field_name = "id",
    }

    -- XXX potentially dangerous historical assumption: plugin only
    -- belongs to one workspace; if it's shared, its workspace scope
    -- (used to fetch entities the plugin needs, such as credentials),
    -- will have length > 1, so we can't safely pick the 1st workspace
    local ws = plugin_workspaces[1]

    if ws then
      plugin.workspace_id = ws.workspace_id
      plugin.workspace_name = ws.workspace_name
    end

    local ws_scope = ngx.ctx.workspaces or {}
    found = #ws_scope == 0 -- if ws_scope is empty, it means global scope,
                                 -- so return true
    for _, ws in ipairs(ws_scope) do
      if ws.id == plugin.workspace_id then
        found = true
      end
    end
  end

  -- no plugin was found or plugin was found but doesn't belong to current
  -- workspace scope
  return found and plugin
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

            -- if workspace scope isn't empty,
            if ws_scope and ws_scope[1] then
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
