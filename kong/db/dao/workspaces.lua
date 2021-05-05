local Workspaces = {}


function Workspaces:truncate()
  self.super.truncate(self)
  if kong.configuration.database == "off" then
    return true
  end

  local name = "default"
  local default_ws, err = self:upsert_by_name(name, { name = name })
  if err then
    kong.log.err(err)
    return
  end

  ngx.ctx.workspace = default_ws.id
  kong.default_workspace = default_ws.id
end


return Workspaces
