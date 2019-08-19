local rbac       = require "kong.rbac"
local RbacRoleEndpoints = {}

-- Warning: This method does *not* use pagination to iterate over the rows
-- Instead, it selects all the permissions associated to one endpoint in one sql request,
-- and then returns an iterator over that table
function RbacRoleEndpoints:all_by_endpoint(endpoint, workspace, options)
  -- In practice, it is very unlikely that this will return more than a handful of records
  local rows, err_t = self.strategy:all_by_endpoint(endpoint, workspace, options)
  if err_t then
    return nil, tostring(err_t), err_t
  end

  local entities, err
  entities, err, err_t = self:rows_to_entities(rows, options)
  if not entities then
    return nil, err, err_t
  end

  if not options or not options.skip_rbac then
    entities = rbac.narrow_readable_entities(self.schema.name, entities)
  end

  return entities
end

return RbacRoleEndpoints
