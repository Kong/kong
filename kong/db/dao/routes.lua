local RoutesDAO = {}


function RoutesDAO:for_service(service_id)
  self:check_arg(service_id, 1, 'string')

  -- This DAO is abstract and sitting on top of the strategy,
  -- because custom DAOs might have custom arg checks, and custom
  -- permissions checks as well.
  -- Hence, we need the following layers:
  --     kong.db
  --        kong.db.dao (or custom DAO)
  --          kong.db.strategy....  (generic strategy or custom strategy)

  return self.strategy:for_service(service_id)
end


return RoutesDAO
