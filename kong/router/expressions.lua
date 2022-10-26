local _M = {}


local atc = require("kong.router.atc")
local gen_for_field = atc.gen_for_field


local OP_EQUAL    = "=="
local LOGICAL_AND = atc.LOGICAL_AND


local function get_exp_and_priority(route)
  local exp = route.expression
  if not exp then
    return
  end

  local gen = gen_for_field("net.protocol", OP_EQUAL, route.protocols)
  if gen then
    exp = exp .. LOGICAL_AND .. gen
  end

  return exp, route.priority
end


function _M.new(routes, cache, cache_neg, old_router)
  return atc.new(routes, cache, cache_neg, old_router, get_exp_and_priority)
end


-- for unit-testing purposes only
_M._set_ngx = atc._set_ngx


return _M
