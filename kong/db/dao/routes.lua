-- NOTE: this DAO is not enabled when router_flavor = expressions, see schema/entities/routes.lua


local Routes = {}


local process_route
do
  local get_atc = require("kong.router.atc_compat").get_atc
  local constants = require("kong.constants")

  local PROTOCOLS_WITH_SUBSYSTEM = constants.PROTOCOLS_WITH_SUBSYSTEM

  process_route = function(self, pk, route, options)
    for _, protocol in ipairs(route.protocols) do
      if PROTOCOLS_WITH_SUBSYSTEM[protocol] == "stream" then
        return route
      end
    end

    local expression = get_atc(route)
    if route.expression ~= expression then
      route.expression = expression

      local _, err, err_t = self.super.update(self, pk,
                                              { expression = expression, },
                                              options)
      if err then
        return nil, err, err_t
      end
    end

    return route
  end
end


local ERR_READONLY = "field is readonly unless Router Expressions feature is enabled"


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

  return process_route(self, { id = entity.id, }, entity, options)
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

  return process_route(self, pk, entity, options)
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

  return process_route(self, pk, entity, options)
end



return Routes
