local base = require "resty.core.base"


local workspaces = {}


function workspaces.upsert_default()
  local old_default_ws_id = kong.default_workspace
  local default_ws, err = kong.db.workspaces:select_by_name("default")
  if err then
    return nil, err
  end
  if not default_ws then
    default_ws, err = kong.db.workspaces:insert({ name = "default" })
    if not default_ws then
      return nil, err
    end
  end
  ngx.ctx.workspace = default_ws and default_ws.id
  kong.default_workspace = default_ws and default_ws.id

  if old_default_ws_id ~= default_ws.id then
    kong.log.debug("default workspace id changed from ", old_default_ws_id,
                   " to ", default_ws.id)
  end

  return default_ws
end


function workspaces.get_workspace()
  local ws_id = ngx.ctx.workspace or kong.default_workspace
  return kong.db.workspaces:select({ id = ws_id })
end


function workspaces.set_workspace(ws)
  ngx.ctx.workspace = ws and ws.id
end


function workspaces.get_workspace_id()
  local ws_id = kong.default_workspace
  if ws_id == nil and base.get_request() then
    kong.default_workspace = ngx.ctx.workspace
    ws_id = kong.default_workspace
  end

  return ws_id
--   local r = base.get_request()
--   if not r then
--     return nil
--   end
--
--   return ngx.ctx.workspace or kong.default_workspace
end

function workspaces.set_workspace_id(--[[ws_id]])
--   ngx.ctx.workspace = ws_id
end


return workspaces
