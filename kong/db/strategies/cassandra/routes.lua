local cassandra = require "cassandra"


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

  for i = 1, #plugins do
    local res, err = connector:query("DELETE FROM plugins WHERE id = ?", {
      cassandra.uuid(plugins[i].id)
    }, nil, "write")
    if not res then
      return nil, self.errors:database_error("could not delete plugin " ..
                                              "associated with Route: " .. err)
    end
  end

  return true
end


return _Routes
