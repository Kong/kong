local workspaces = require "kong.workspaces"
local rbac       = require "kong.rbac"


local fmt = string.format


local _Routes_ee = {}


function _Routes_ee:delete(primary_key)
  local plugins = {}
  local constraints = workspaces.get_workspaceable_relations()[self.schema.name]

  -- retrieve plugins associated with this Route
  local select_q = fmt("SELECT * FROM plugins WHERE route_id = '%s'",
                       primary_key.id)

  for row, err in self.connector:iterate(select_q) do
    if err then
      return nil, self.errors:database_error("could not fetch plugins " ..
                                             "for Route: " .. err)
    end

    if not rbac.validate_entity_operation(row, constraints) then
      -- todo return correct error
      return nil, self.errors:unauthorized_operation("cascading delete")
    end

    table.insert(plugins, row)
  end


  if not rbac.validate_entity_operation(primary_key, constraints) then
    -- todo return correct error
    return nil, self.errors:unauthorized_operation("delete")
  end

  local ok, err_t = self.super.delete(self, primary_key)
  if not ok then
    return nil, err_t
  end

  -- CASCADE delete workspace relationship
  local ws = workspaces.get_workspaces()[1]
  for i = 1, #plugins do
    if ws then
      local err = workspaces.delete_entity_relation("plugins", {id = plugins[i].id})
      if err then
        return nil, self.errors:database_error("could not delete Plugin relationship " ..
          "with Workspace: " .. err)
      end
    end
  end

  if ok and ws then
    local err = workspaces.delete_entity_relation("routes", {id = primary_key.id})
    if err then
      return nil, self.errors:database_error("could not delete Route relationship " ..
                                             "with Workspace: " .. err)
    end
  end

  return true
end


return _Routes_ee
