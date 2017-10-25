local _Routes = {}


do
  --[=[
  local cql_insert_route = [[

  ]]

  local cql_service_exists = [[

  ]]

  local cql_attach_route_to_service = [[

  ]]
  --]=]

  function _Routes:insert(route)
    --local schema = self.schema

    -- test if route.service
    --  if so, serialize route.service
    --  check service exists
    -- serialize args for route
    -- insert route
    -- update service with the reference to the new route's id
  end
end


function _Routes:update()
  -- update in 'routes' and also in 'services.routes' if the route
  -- has a service
  return "custom update"
end


return _Routes
