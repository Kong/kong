local base = require "resty.core.base"


local workspaces = {}


function workspaces.upsert_default()
  local old_default_ws_id = kong.default_workspace
  local name = "default"

  local default_ws, err = kong.db.workspaces:select_by_name(name)
  if err then
    return nil, err
  end
  if not default_ws then
    default_ws, err = kong.db.workspaces:upsert_by_name(name, { name = name })
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
  if not ws_id or ws_id == ngx.null then
    return kong.db.workspaces:select_by_name("default")
  end

  return kong.db.workspaces:select({ id = ws_id })
end


function workspaces.set_workspace(ws)
  if ws and ws.id then
    ngx.ctx.workspace = ws.id
  end
end


function workspaces.get_workspace_id(ctx)
  local r = base.get_request()
  local inspect = require "inspect"
  if not r then
    ngx.log(ngx.ERR, "GET WORKSPACE ID (NO REQUEST): ", inspect(kong and kong.default_workspace))
    return kong and kong.default_workspace
  end

  ngx.log(ngx.ERR, "GET WORKSPACE ID (WITH REQUEST): ", inspect((ctx or ngx.ctx).workspace))
  ngx.log(ngx.ERR, "GET WORKSPACE ID DEFAULT (WITH REQUEST): ", inspect(kong and kong.default_workspace))
  return (ctx or ngx.ctx).workspace or (kong and kong.default_workspace)
end


return workspaces
