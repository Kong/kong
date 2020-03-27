local split = require("pl.stringx").split
local ws_scope_as_list = require("kong.workspaces").ws_scope_as_list


local insert = table.insert


local Plugins = {}


-- XXX: EE . Leftover of 1.2.0 merge. This file does not exist there anymore
-- Keeping it for workspaces. Possibly delete once ws-in-core is real
function Plugins:select_by_field(field, value, options)
  local plugin, err = self.super.select_by_field(self, field, value, options)
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
    local plugin_workspaces = kong.db.workspace_entities:select_all({
      entity_id = plugin.id,
      unique_field_name = "id",
    }, {skip_rbac = true})

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
