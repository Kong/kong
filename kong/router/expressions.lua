local _M = {}


local atc = require("kong.router.atc")
local transform = require("kong.router.transform")


local get_priority   = transform.get_priority
local amending_expression = transform.amending_expression


local gen_for_field = transform.gen_for_field
local OP_EQUAL      = transform.OP_EQUAL
local LOGICAL_AND   = transform.LOGICAL_AND


-- map to normal protocol
local PROTOCOLS_OVERRIDE = {
  tls_passthrough = "tcp",
  grpc            = "http",
  grpcs           = "https",
}


local function get_exp_and_priority(route)
  local exp = amending_expression(route)
  if not exp then
    ngx.log(ngx.ERR, "expecting an expression route while it's not (probably a traditional route). ",
                     "Likely it's a misconfiguration. Please check the 'router_flavor' config in kong.conf")
    return
  end

  local priority = get_priority(route)

  local protocols = route.protocols

  -- give the chance for http redirection (301/302/307/308/426)
  -- and allow tcp works with tls
  if protocols and #protocols == 1 and
    (protocols[1] == "https" or
     protocols[1] == "tls" or
     protocols[1] == "tls_passthrough")
  then
    return exp, priority
  end

  local gen = gen_for_field("net.protocol", OP_EQUAL, protocols,
                            function(_, p)
                              return PROTOCOLS_OVERRIDE[p] or p
                            end)
  if gen then
    exp = exp .. LOGICAL_AND .. gen
  end

  return exp, priority
end


function _M.new(routes, cache, cache_neg, old_router)
  return atc.new(routes, cache, cache_neg, old_router, get_exp_and_priority)
end


-- for unit-testing purposes only
_M._set_ngx = atc._set_ngx


return _M
