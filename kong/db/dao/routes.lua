-- NOTE: this DAO is not enabled when router_flavor = expressions, see schema/entities/routes.lua


local get_atc = require("kong.router.atc_compat").get_atc
local constants = require("kong.constants")


local _Routes = {}


local ERR_READONLY = "field is readonly unless Router Expressions feature is enabled"
local PROTOCOLS_WITH_SUBSYSTEM = constants.PROTOCOLS_WITH_SUBSYSTEM


local function process_route(self, route_pk, route, options)
  for _, protocol in ipairs(route.protocols) do
    if PROTOCOLS_WITH_SUBSYSTEM[protocol] == "stream" then
      return route
    end
  end

  local expression = get_atc(route)
  if route.expression ~= expression then
    route.expression = get_atc(route)

    local err, err_t
    route, err, err_t = self.super.update(self, route_pk,
                                          { expression = route.expression, },
                                          options)
    if err then
      return nil, err, err_t
    end
  end

  return route
end


-- If router is running in traditional or traditional compatible mode,
-- generate the corresponding ATC DSL and persist it to the `expression` field
function _Routes:insert(route, options)
  if route.expression then
    local err_t = self.errors:schema_violation({
      expression = ERR_READONLY,
    })

    return nil, tostring(err_t), err_t
  end

  local err, err_t
  route, err, err_t = self.super.insert(self, route, options)
  if not route then
    return nil, err, err_t
  end

  route, err, err_t = process_route(self, { id = route.id, }, route, options)
  if not route then
    return nil, err, err_t
  end

  return route
end


function _Routes:update(route_pk, route, options)
  if route.expression then
    local err_t = self.errors:schema_violation({
      expression = ERR_READONLY,
    })

    return nil, tostring(err_t), err_t
  end

  local err, err_t
  route, err, err_t = self.super.update(self, route_pk, route, options)
  if err then
    return nil, err, err_t
  end

  route, err, err_t = process_route(self, route_pk, route, options)
  if not route then
    return nil, err, err_t
  end

  return route
end


function _Routes:upsert(route_pk, route, options)
  if not options.is_db_import and route.expression then
    local err_t = self.errors:schema_violation({
      expression = ERR_READONLY,
    })

    return nil, tostring(err_t), err_t
  end

  local err, err_t
  route, err, err_t = self.super.upsert(self, route_pk, route, options)
  if err then
    return nil, err, err_t
  end

  route, err, err_t = process_route(self, route_pk, route, options)
  if not route then
    return nil, err, err_t
  end


  return route
end


return _Routes
