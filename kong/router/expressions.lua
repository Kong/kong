local _M = {}


local atc = require("kong.router.atc")
local gen_for_field = atc.gen_for_field


local OP_EQUAL = "=="


local function get_exp_priority(route)
  local exp = route.expression
  if not exp then
    return
  end

  local gen = gen_for_field("net.protocol", OP_EQUAL, route.protocols)
  if gen then
    exp = exp .. " && " .. gen
  end

  return exp, route.priority
end


function _M.new(routes, cache, cache_neg, old_router)
  return atc.new(routes, cache, cache_neg, old_router, get_exp_priority)
end


-- for unit-testing purposes only
_M._set_ngx = atc._set_ngx


return _M
