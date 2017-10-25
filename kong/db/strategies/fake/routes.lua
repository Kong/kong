local Routes = {}

function Routes:for_service(service_id)
  local routes = self.entities
  local key
  local route
  return function()
    repeat
      key, route = next(routes, key)
      if route then
        if route.service.id == service_id then
          return route
        end
      end
    until not key
  end
end

return Routes
