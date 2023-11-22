-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local Services = {}

local null = ngx.null

local function check_protocol(self, old, new)
  if new.protocol == nil or new.protocol == null then
    return true
  end

  local old_ws = old.protocol == "ws" or
                 old.protocol == "wss"

  local new_ws = new.protocol == "ws" or
                 new.protocol == "wss"

  local err_t
  if old_ws and not new_ws then
    err_t = self.errors:schema_violation({
      protocol = "cannot change WebSocket protocol to non-WebSocket protocol",
    })
    return nil, tostring(err_t), err_t

  elseif new_ws and not old_ws then
    err_t = self.errors:schema_violation({
      protocol = "cannot change non-WebSocket protocol to WebSocket protocol",
    })
    return nil, tostring(err_t), err_t
  end

  return true
end


function Services:upsert(pk, entity, options)
  local current = self.super.select(self, pk, options)
  if current then
    local ok, err, err_t = check_protocol(self, current, entity)
    if not ok then
      return nil, err, err_t
    end
  end

  return self.super.upsert(self, pk, entity, options)
end


function Services:update(pk, entity, options)
  local current = self.super.select(self, pk, options)

  if current then
    entity = self.schema:merge_values(entity, current)

    local ok, err, err_t = check_protocol(self, current, entity)
    if not ok then
      return nil, err, err_t
    end
  end

  return self.super.update(self, pk, entity, options)
end


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
