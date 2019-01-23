---
-- The service module contains a set of functions to manipulate the connection
-- aspect of the request to the Service, such as connecting to a given host, IP
-- address/port, or choosing a given Upstream entity for load-balancing and
-- healthchecking.
--
-- @module kong.service


local balancer = require "kong.runloop.balancer"
local phase_checker = require "kong.pdk.private.phases"


local ngx = ngx
local check_phase = phase_checker.check


local PHASES = phase_checker.phases


local function new()
  local service = {}


  ---
  -- Sets the desired Upstream entity to handle the load-balancing step for
  -- this request. Using this method is equivalent to creating a Service with a
  -- `host` property equal to that of an Upstream entity (in which case, the
  -- request would be proxied to one of the Targets associated with that
  -- Upstream).
  --
  -- The `host` argument should receive a string equal to that of one of the
  -- Upstream entities currently configured.
  --
  -- @function kong.service.set_upstream
  -- @phases access
  -- @tparam string host
  -- @treturn boolean|nil `true` on success, or `nil` if no upstream entities
  -- where found
  -- @treturn string|nil An error message describing the error if there was
  -- one.
  --
  -- @usage
  -- local ok, err = kong.service.set_upstream("service.prod")
  -- if not ok then
  --   kong.log.err(err)
  --   return
  -- end
  function service.set_upstream(host)
    check_phase(PHASES.access)

    if type(host) ~= "string" then
      error("host must be a string", 2)
    end

    local upstream = balancer.get_upstream_by_name(host)
    if not upstream then
      return nil, "could not find an Upstream named '" .. host .. "'"
    end

    ngx.ctx.balancer_data.host = host
    return true
  end


  ---
  -- Sets the host and port on which to connect to for proxying the request. ]]
  -- Using this method is equivalent to ask Kong to not run the load-balancing
  -- phase for this request, and consider it manually overridden.
  -- Load-balancing components such as retries and health-checks will also be
  -- ignored for this request.
  --
  -- The `host` argument expects a string containing the IP address of the
  -- upstream server (IPv4/IPv6), and the `port` argument must contain a number
  -- representing the port on which to connect to.
  --
  -- @function kong.service.set_target
  -- @phases access
  -- @tparam string host
  -- @tparam number port
  -- @usage
  -- kong.service.set_target("service.local", 443)
  -- kong.service.set_target("192.168.130.1", 80)
  function service.set_target(host, port)
    check_phase(PHASES.access)

    if type(host) ~= "string" then
      error("host must be a string", 2)
    end
    if type(port) ~= "number" or math.floor(port) ~= port then
      error("port must be an integer", 2)
    end
    if port < 0 or port > 65535 then
      error("port must be an integer between 0 and 65535: given " .. port, 2)
    end

    ngx.var.upstream_host = host
    ngx.ctx.balancer_data.host = host
    ngx.ctx.balancer_data.port = port
  end


  return service
end


return {
  new = new,
}
