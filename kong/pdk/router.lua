--- Router module
-- A set of functions to access the routing properties of the request.
--
-- @module kong.router


local phase_checker = require "kong.pdk.private.phases"


local ngx = ngx
local check_phase = phase_checker.check


local PHASES = phase_checker.phases
local ROUTER_PHASES = phase_checker.new(PHASES.access,
                                        PHASES.header_filter,
                                        PHASES.body_filter,
                                        PHASES.log)

local function new(self)
  local _ROUTER = {}


  ---
  -- Returns the current `route` entity. The request was matched against this
  -- route.
  --
  -- @function kong.router.get_route
  -- @phases access, header_filter, body_filter, log
  -- @treturn table the `route` entity.
  -- @usage
  -- local route = kong.router.get_route()
  -- local protocols = route.protocols
  function _ROUTER.get_route()
    check_phase(ROUTER_PHASES)

    return ngx.ctx.route
  end


  ---
  -- Returns the current `service` entity. The request will be targetted to this
  -- upstream service.
  --
  -- @function kong.router.get_service
  -- @phases access, header_filter, body_filter, log
  -- @treturn table the `service` entity.
  -- @usage
  -- if kong.router.get_service() then
  --   -- routed by route & service entities
  -- else
  --   -- routed by a route without a service
  -- end
  function _ROUTER.get_service()
    check_phase(ROUTER_PHASES)

    return ngx.ctx.service
  end


  return _ROUTER
end


return {
  new = new,
}
