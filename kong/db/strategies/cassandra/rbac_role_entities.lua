-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cassandra = require "cassandra"

local CQL = [[
  SELECT role_id, entity_id FROM rbac_role_entities WHERE entity_id = ? AND entity_type = ? ALLOW FILTERING
]]

local DELETE_CQL = [[
  DELETE FROM rbac_role_entities WHERE role_id = ? AND entity_id = ?
]]

local RbacRoleEntities = {}


function RbacRoleEntities:select_role_entity_permission(entity_id, entity_type, options)
  -- cassandra.text don't support nil argument, cassandra don't support null value as well
  -- so empty string is used when value is nil
  entity_id   = entity_id or ''
  entity_type = entity_type or ''
  local args  = { cassandra.text(entity_id), cassandra.text(entity_type) }

  local rows, err = self.connector:query(CQL, args, options, "read")
  if not rows then
    return nil, self.errors:database_error("could not execute query: " .. err)
  end

  for i = 1, #rows do
    rows[i] = self:deserialize_row(rows[i])
  end

  return rows
end

function RbacRoleEntities:delete_role_entity_permission(entity_id, entity_type, options)
  local rows, err_t = self:select_role_entity_permission(entity_id, entity_type, options)
  if err_t then
    return rows, err_t
  end

  if rows == nil then
    return
  end

  for _, role_entity in ipairs(rows) do
    local args  = { cassandra.uuid(role_entity.role.id), cassandra.text(entity_id) }
    err_t = self.connector:query(DELETE_CQL, args, options, "write")
    if err_t then
      return err_t
    end
  end
end

return RbacRoleEntities