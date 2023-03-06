-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local fmt = string.format

local RbacRoleEntities = {}

local DELETE_SQL = [[
  DELETE FROM rbac_role_entities WHERE entity_id = %s AND entity_type = %s;
]]

function RbacRoleEntities:delete_role_entity_permission(entity_id, entity_type)
  local sql = fmt(DELETE_SQL, self:escape_literal(entity_id), self:escape_literal(entity_type))
  local res, err = self.connector:query(sql)
  if not res then
    return nil, self.errors:database_error(err)
  end
end

return RbacRoleEntities
