local portal_helpers = require "kong.portal.dao_helpers"

local _Workspaces = {}


function _Workspaces:insert(entity, options)
  local entity, err = portal_helpers.set_portal_auth_conf({}, entity)
  if not entity then
    return kong.response.exit(400, { message = err })
  end

  return self.super.insert(self, entity, options)
end


function _Workspaces:update(workspace_pk, entity, options)
  local ws, err, err_t = self.db.workspaces:select({ id = workspace_pk.id })
  if err then
    return nil, err, err_t
  end

  entity, err = portal_helpers.set_portal_auth_conf(ws, entity)
  if not entity then
    return kong.response.exit(400, { message = err })
  end


  return self.super.update(self, { id = ws.id }, entity, options)
end


function _Workspaces:update_by_name(workspace_name, entity, options)
  local ws, err, err_t = self.db.workspaces:select_by_name(workspace_name)
  if err then
    return nil, err, err_t
  end

  entity, err = portal_helpers.set_portal_auth_conf(ws, entity)
  if not entity then
    return kong.response.exit(400, { message = err })
  end

  return self.super.update(self, { id = ws.id }, entity, options)
end


return _Workspaces
