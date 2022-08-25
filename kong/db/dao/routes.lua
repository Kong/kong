-- NOTE: this DAO is not enabled when router_flavor = expressions, see schema/entities/routes.lua


local get_atc = require("kong.router.atc_compat").get_atc
local constants = require("kong.constants")


local Routes = {}


local ERR_READONLY = "field is readonly unless Router Expressions feature is enabled"
local PROTOCOLS_WITH_SUBSYSTEM = constants.PROTOCOLS_WITH_SUBSYSTEM


local function process_route(self, pk, route, options)
  for _, protocol in ipairs(route.protocols) do
    if PROTOCOLS_WITH_SUBSYSTEM[protocol] == "stream" then
      return route
    end
  end

  local expression = get_atc(route)
  if route.expression ~= expression then
    route.expression = get_atc(route)

    local _, err, err_t = self.super.update(self, pk,
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
function Routes:insert(entity, options)
  if entity and entity.expression then
    local err_t = self.errors:schema_violation({
      expression = ERR_READONLY,
    })

    return nil, tostring(err_t), err_t
  end

  local err, err_t
  entity, err, err_t = self.super.insert(self, entity, options)
  if not entity then
    return nil, err, err_t
  end

  entity, err, err_t = process_route(self, { id = entity.id, }, entity, options)
  if not entity then
    return nil, err, err_t
  end

  return entity
end


function Routes:upsert(pk, entity, options)
  if not options.is_db_import and entity and entity.expression then
    local err_t = self.errors:schema_violation({
      expression = ERR_READONLY,
    })

    return nil, tostring(err_t), err_t
  end

  local err, err_t
  entity, err, err_t = self.super.upsert(self, pk, entity, options)
  if err then
    return nil, err, err_t
  end

  entity, err, err_t = process_route(self, pk, entity, options)
  if not entity then
    return nil, err, err_t
  end

  return entity
end


function Routes:update(pk, entity, options)
  if entity and entity.expression then
    local err_t = self.errors:schema_violation({
      expression = ERR_READONLY,
    })

    return nil, tostring(err_t), err_t
  end

  local err, err_t
  entity, err, err_t = self.super.update(self, pk, entity, options)
  if err then
    return nil, err, err_t
  end

  entity, err, err_t = process_route(self, pk, entity, options)
  if not entity then
    return nil, err, err_t
  end

  return entity
end



return Routes
