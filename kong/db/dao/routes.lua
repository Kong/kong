local router = require("resty.router.router")
local CACHED_SCHEMA = require("kong.router.atc").schema
local _get_expression = require("kong.router.compat")._get_expression


local kong = kong


local _Routes = {}


local function check_route(route)
  if kong.configuration.router_flavor ~= "traditional_compatible" then
    return true
  end

  -- router_flavor == "traditional_compatible"

  local r = router.new(CACHED_SCHEMA)
  local exp = _get_expression(route)

  local res, err = r:add_matcher(0, route.id, exp)
  if not res then
    return nil, err
  end

  return true
end


function _Routes:insert(entity, options)
  local ok, err = check_route(entity)
  if not ok then
    return nil, err
  end

  return self.super.insert(self, entity, options)
end


function _Routes:upsert(pk, entity, options)
  local ok, err = check_route(entity)
  if not ok then
    return nil, err
  end

  return self.super.upsert(self, pk, entity, options)
end


function _Routes:update(pk, entity, options)
  local ok, err = check_route(entity)
  if not ok then
    return nil, err
  end

  return self.super.update(self, pk, entity, options)
end


return _Routes
