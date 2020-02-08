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


return Plugins
