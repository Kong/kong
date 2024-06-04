local _M = {}


local atc = require("kong.router.atc")
local transform = require("kong.router.transform")


local get_expression  = transform.get_expression
local get_priority    = transform.get_priority


local function get_exp_and_priority(route)
  if route.expression then
    ngx.log(ngx.ERR, "expecting a traditional route while it's not (probably an expressions route). ",
                     "Likely it's a misconfiguration. Please check the 'router_flavor' config in kong.conf")
  end

  local exp      = get_expression(route)
  local priority = get_priority(route)

  return exp, priority
end


function _M.new(routes_and_services, cache, cache_neg, old_router)
  return atc.new(routes_and_services, cache, cache_neg, old_router, get_exp_and_priority)
end


-- for unit-testing purposes only
_M._set_ngx = atc._set_ngx


return _M
