-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

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
