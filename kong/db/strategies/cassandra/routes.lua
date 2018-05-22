local cassandra = require "cassandra"
local workspaces = require "kong.workspaces"


local _Routes = {}


function _Routes:delete(primary_key)
  local ok, err_t = self.super.delete(self, primary_key)
  if not ok then
    return nil, err_t
  end

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
      table.insert(plugins, rows[i])
    end
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
      local err = workspaces.delete_entity_relation("plugins", {id = plugins[i].id})
      if err then
        return nil, self.errors:database_error("could not delete Plugin relationship " ..
                                               "with Workspace: " .. err)
      end
    end
  end

  if ok and ws then
    local err = workspaces.delete_entity_relation("routes", {id = primary_key})
    if err then
      return nil, self.errors:database_error("could not delete Route relationship " ..
                                             "with Workspace: " .. err)
    end
  end

  return true
end


return _Routes
