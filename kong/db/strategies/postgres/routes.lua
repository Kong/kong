local workspaces = require "kong.workspaces"
local rbac       = require "kong.rbac"


local fmt = string.format


local _Routes_ee = {}


function _Routes_ee:delete(primary_key, options)
  local plugins = {}

  -- retrieve plugins associated with this Route
  local select_q = fmt("SELECT * FROM plugins WHERE route_id = '%s'",
                       primary_key.id)

  for row, err in self.connector:iterate(select_q) do
    if err then
      return nil, self.errors:database_error("could not fetch plugins " ..
                                             "for Route: " .. err)
    end

    if not rbac.validate_entity_operation(row, self.schema.name) then
      return nil, self.errors:unauthorized_operation({
        username = ngx.ctx.rbac.user.name,
        action = rbac.readable_action(ngx.ctx.rbac.action)
      })
    end

    table.insert(plugins, row)
  end


  if not options or not options.skip_rbac then
    if not rbac.validate_entity_operation(primary_key, self.schema.name) then
      return nil, self.errors:unauthorized_operation({
        username = ngx.ctx.rbac.user.name,
        action = rbac.readable_action(ngx.ctx.rbac.action)
      })
    end
  end

  local ok, err_t = self.super.delete(self, primary_key)
  if not ok then
    return nil, err_t
  end

  -- CASCADE delete workspace relationship
  local ws = workspaces.get_workspaces()[1]
  for i = 1, #plugins do
    if ws then
      local err = workspaces.delete_entity_relation("plugins", plugins[i])
      if err then
        return nil, self.errors:database_error("could not delete Plugin relationship " ..
                                               "with Workspace: " .. err)
      end

      err = rbac.delete_role_entity_permission("plugins", plugins[i])
      if err then
        return nil, self.errors:database_error("could not delete Plugin relationship " ..
                                               "with Role: " .. err)
      end
    end
  end

  return true, nil, primary_key
end


return _Routes_ee
