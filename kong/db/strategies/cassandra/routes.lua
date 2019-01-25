local cassandra = require "cassandra"
local workspaces = require "kong.workspaces"
local rbac       = require "kong.rbac"


local _Routes_ee = {}


function _Routes_ee:delete(primary_key, options)
  local plugins = {}
  local connector = self.connector
  local cluster = connector.cluster

  -- retrieve plugins associated with this Route
  local query = "SELECT * FROM plugins WHERE route_id = ? ALLOW FILTERING"
  local args = { cassandra.uuid(primary_key.id) }

  for rows, err in cluster:iterate(query, args) do
    if err then
      return nil, self.errors:database_error("could not fetch plugins " ..
        "for Route: " .. err)
    end

    for i = 1, #rows do
      if not rbac.validate_entity_operation(rows[i], self.schema.name) then
        return nil, self.errors:unauthorized_operation({
          username = ngx.ctx.rbac.user.name,
          action = rbac.readable_action(ngx.ctx.rbac.action)
        })
      end
      table.insert(plugins, rows[i])
    end
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

  -- CASCADE delete associated plugins
  local ws = workspaces.get_workspaces()[1]
  for i = 1, #plugins do
    local res, err = connector:query("DELETE FROM plugins WHERE id = ?", {
      cassandra.uuid(plugins[i].id)
    }, nil, "write")
    if not res then
      return nil, self.errors:database_error("could not delete plugin " ..
        "associated with Route: " .. err)
    end

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

  if ok and ws then
    local err = workspaces.delete_entity_relation("routes", primary_key)
    if err then
      return nil, self.errors:database_error("could not delete Route relationship " ..
                                             "with Workspace: " .. err)
    end

    err = rbac.delete_role_entity_permission("routes", primary_key)
    if err then
      return nil, self.errors:database_error("could not delete Route relationship " ..
                                             "with Role: " .. err)
    end
  end

  return true, nil, primary_key
end


return _Routes_ee
