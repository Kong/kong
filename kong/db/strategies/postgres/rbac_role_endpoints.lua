local fmt           = string.format

local RbacRoleEndpoints = {}


local SQL = [[
  SELECT role_id, workspace, endpoint, actions, negative, comment, extract('epoch' from created_at at time zone 'UTC') as created_at
  FROM rbac_role_endpoints
  WHERE workspace = %s
  AND endpoint = %s
  ORDER BY created_at;
]]


function RbacRoleEndpoints:all_by_endpoint(endpoint, workspace)
  local sql = fmt(SQL, self:escape_literal(workspace), self:escape_literal(endpoint))

  local res, err = self.connector:query(sql)
  if not res then
    return nil, self.errors:database_error(err)
  end

  for i = 1, #res do
    res[i] = self.expand(res[i])
  end

  return res
end


return RbacRoleEndpoints
