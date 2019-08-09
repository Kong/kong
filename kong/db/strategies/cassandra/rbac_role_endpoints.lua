local cassandra = require "cassandra"

local CQL = [[
  SELECT role_id, workspace, endpoint, actions, negative, comment, created_at
  FROM rbac_role_endpoints WHERE workspace = ? AND endpoint = ? ALLOW FILTERING
]]


local RbacRoleEndpoints = {}


function RbacRoleEndpoints:all_by_endpoint(endpoint, workspace, options)
  local args = { cassandra.text(workspace), cassandra.text(endpoint) }

  local rows, err = self.connector:query(CQL, args, options, "read")
  if not rows then
    return nil, self.errors:database_error("could not execute query: " .. err)
  end

  for i = 1, #rows do
    rows[i] = self:deserialize_row(rows[i])
  end

  return rows
end


return RbacRoleEndpoints
