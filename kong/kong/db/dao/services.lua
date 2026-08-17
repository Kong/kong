
local Services = {}

-- @ca_id: the id of ca certificate to be searched
-- @limit: the maximum number of entities to return (must >= 0)
-- @return an array of the service entity
function Services:select_by_ca_certificate(ca_id, limit)
  local services, err = self.strategy:select_by_ca_certificate(ca_id, limit)
  if err then
    return nil, err
  end

  return self:rows_to_entities(services), nil
end

return Services
