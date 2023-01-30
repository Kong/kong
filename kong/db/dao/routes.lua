-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local Routes = {}

local type = type

local function is_websocket(route)
  if type(route.protocols) ~= "table" then
    return false
  end

  for _, proto in ipairs(route.protocols) do
    if proto == "ws" or proto == "wss" then
      return true
    end
  end

  return false
end


local function check_protocols(self, route)
  -- the parent DAO will handle this case
  if type(route) ~= "table" then
    return true
  end

  local service
  local err_t
  local ws_route = is_websocket(route)

  if type(route.service) == "table" then
    service = kong.db.services:select({ id = route.service.id })

    -- the parent DAO will handle this case
    if not service then
      return true
    end

  elseif ws_route then
    err_t = self.errors:schema_violation({
      service = "WebSocket routes must be attached to a service",
    })
    return nil, tostring(err_t), err_t

  else
    return true
  end

  local ws_service = service.protocol == "ws" or
                     service.protocol == "wss"

  if ws_route ~= ws_service then
    err_t = self.errors:schema_violation({
      protocols = "route/service protocol mismatch",
    })
    return nil, tostring(err_t), err_t
  end

  return true
end


function Routes:insert(entity, options)
  local ok, err, err_t = check_protocols(self, entity)
  if not ok then
    return nil, err, err_t
  end

  return self.super.insert(self, entity, options)
end


function Routes:upsert(pk, entity, options)
  local ok, err, err_t = check_protocols(self, entity)
  if not ok then
    return nil, err, err_t
  end

  return self.super.upsert(self, pk, entity, options)
end


function Routes:update(pk, entity, options)
  local current = self.super.select(self, pk, options)
  if current then
    entity = self.schema:merge_values(entity, current)

    local ok, err, err_t = check_protocols(self, entity)
    if not ok then
      return nil, err, err_t
    end
  end

  return self.super.update(self, pk, entity, options)
end




function Routes:check_route_overlap(paths, hosts, methods, current_route)
  local rows, err_t = self.strategy:check_route_overlap(paths, hosts, methods, current_route)
  if err_t then
    return nil, tostring(err_t), err_t
  end

  local entities, err
  local options = { show_ws_id = true }
  entities, err, err_t = self:rows_to_entities(rows, options)
  if not entities then
    return nil, err, err_t
  end

  return entities
end

return Routes
