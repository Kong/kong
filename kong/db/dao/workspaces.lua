local portal_helpers = require "kong.portal.dao_helpers"


local Workspaces = {}


function Workspaces:insert(entity, options)
  local entity, err = portal_helpers.set_portal_conf({}, entity)
  if not entity then
    return kong.response.exit(400, { message = err })
  end

  return self.super.insert(self, entity, options)
end


function Workspaces:update(workspace_pk, entity, options)
  local ws, err, err_t = self.db.workspaces:select({ id = workspace_pk.id })
  if err then
    return nil, err, err_t
  end

  local entity, err = portal_helpers.set_portal_conf(ws, entity)
  if not entity then
    return kong.response.exit(400, { message = err })
  end

  return self.super.update(self, { id = ws.id }, entity, options)
end


function Workspaces:update_by_name(workspace_name, entity, options)
  local ws, err, err_t = self.db.workspaces:select_by_name(workspace_name)
  if err then
    return nil, err, err_t
  end

  local entity, err = portal_helpers.set_portal_conf(ws, entity)
  if not entity then
    return kong.response.exit(400, { message = err })
  end

  return self.super.update(self, { id = ws.id }, entity, options)
end


function Workspaces:truncate()
  self.super.truncate(self)
  if kong.configuration.database == "off" then
    return true
  end

  local default_ws, err = self:insert({ name = "default" })
  if err then
    kong.log.err(err)
    return
  end

  ngx.ctx.workspace = default_ws.id
  kong.default_workspace = default_ws.id
end


return Workspaces
