-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local RbacRoleEntities = {}


function RbacRoleEntities:cache_key(id)
  if type(id) == "table" then
    id = id.role.id
  end

  -- Always return the cache_key without a workspace
  return "rbac_role_entities:" .. id .. ":::::"
end

function RbacRoleEntities:delete_role_entity_permission(entity_id, entity_type, options)
  self.strategy:delete_role_entity_permission(entity_id, entity_type, options)
end

return RbacRoleEntities
