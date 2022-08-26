local _M = {}


local atc = require("kong.router.atc")
local gen_for_field = atc.gen_for_field


local OP_EQUAL = "=="


local function get_atc_priority(route)
  local atc = route.expression
  if not atc then
    return
  end

  local priority = route.priority

  local gen = gen_for_field("net.protocol", OP_EQUAL, route.protocols)
  if gen then
    atc = atc .. " && " .. gen
  end

  return atc, priority
end


function _M.new(routes, cache, cache_neg, old_router)
  return atc.new(routes, cache, cache_neg, old_router, get_atc_priority)
end


-- for unit-testing purposes only
--_M._get_atc = get_atc
--_M._route_priority = route_priority


return _M
