-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

--- Router module.
--
-- A set of functions to access the routing properties of the request.
--
-- @module kong.router


local phase_checker = require "kong.pdk.private.phases"


local ngx = ngx
local check_phase = phase_checker.check


local PHASES = phase_checker.phases
local ROUTER_PHASES = phase_checker.new(PHASES.access,
                                        PHASES.header_filter,
                                        PHASES.response,
                                        PHASES.body_filter,
                                        PHASES.log,
                                        PHASES.ws_handshake,
                                        PHASES.ws_proxy,
                                        PHASES.ws_close)

local function new(self)
  local _ROUTER = {}


  ---
  -- Returns the current `route` entity. The request is matched against this
  -- route.
  --
  -- @function kong.router.get_route
  -- @phases access, header_filter, response, body_filter, log
  -- @treturn table The `route` entity.
  -- @usage
  -- local route = kong.router.get_route()
  -- local protocols = route.protocols
  function _ROUTER.get_route()
    check_phase(ROUTER_PHASES)

    return ngx.ctx.route
  end


  ---
  -- Returns the current `service` entity. The request is targeted to this
  -- upstream service.
  --
  -- @function kong.router.get_service
  -- @phases access, header_filter, response, body_filter, log
  -- @treturn table The `service` entity.
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
