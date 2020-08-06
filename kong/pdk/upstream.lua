--- Upstream module
-- Get health for an upstream.
--
-- @module kong.upstream


local phase_checker = require "kong.pdk.private.phases"
local balancer = require "kong.runloop.balancer"
local check_phase = phase_checker.check
local PHASES = phase_checker.phases

local function new()
  local upstream = {}

  ---
  -- Get balancer health for an upstream.
  --
  -- @function kong.upstream.get_balancer_health
  -- @phases access
  -- @tparam string upstream_name
  -- @treturn health_info|nil `health_info` on success, or `nil` if no health_info entities where found
  -- @treturn string|nil An error message describing the error if there was one.
  --
  -- @usage
  -- local health_info, err = kong.upstream.get_balancer_health("example.com")
  -- if not health_info then
  --   kong.log.err(err)
  --   return
  -- end
  --
  -- kong.log.inspect(health_info)
  --
  -- -- Will print
  --  {
  --     health = "HEALTHY",
  --     id = "c49f780a-89cc-44a8-9603-51919bf2990e"
  --  }
  function upstream.get_balancer_health(upstream_name)
    check_phase(PHASES.access)

    if type(upstream_name) ~= "string" then
      error("upstream_name must be a string", 2)
    end

    local upstream = balancer.get_upstream_by_name(upstream_name)
    if not upstream then
      return nil, "could not find an Upstream named '" .. upstream_name .. "'"
    end
    
    local health_info, err = balancer.get_balancer_health(upstream.id)

    if err then
      return nil, "failed getting balancer health '" .. upstream_name .. "'," .. err
    end

    return health_info
  end


  ---
  -- Get healthcheck information for an upstream.
  --
  -- @function kong.upstream.get_upstream_health
  -- @phases access
  -- @tparam string upstream_name
  -- @treturn health_info|nil `health_info` on success, or `nil` if no health_info entities where found
  -- @treturn string|nil An error message describing the error if there was one.
  -- @return health_info:
  -- * if healthchecks are enabled, a table mapping keys ("ip:port") to booleans;
  -- * if healthchecks are disabled, nil;
  --
  -- @usage
  -- local health_info, err = kong.upstream.get_upstream_health("example.com")
  -- if not health_info then
  --   kong.log.err(err)
  --   return
  -- end
  --
  -- kong.log.inspect(health_info)
  --
  -- -- Will print
  -- {
  --     ["10.129.8.172:88"] = {
  --       addresses = {
  --         {
  --          health = "HEALTHY",
  --           ip = "10.129.8.172",
  --           port = 88,
  --           weight = 100
  --         }
  --       },
  --       host = "10.129.8.172",
  --       nodeWeight = 100,
  --       port = 88,
  --       weight = {
  --         available = 100,
  --         total = 100,
  --         unavailable = 0
  --       }
  --     }
  --   }
  function upstream.get_upstream_health(upstream_name)
    check_phase(PHASES.access)

    if type(upstream_name) ~= "string" then
      error("upstream_name must be a string", 2)
    end

    local upstream = balancer.get_upstream_by_name(upstream_name)
    if not upstream then
      return nil, "could not find an Upstream named '" .. upstream_name .. "'"
    end

    local health_info, err = balancer.get_upstream_health(upstream.id)
    if err then
      return nil, "failed getting upstream health '" .. upstream_name .. "'," .. err
    end

    return health_info
  end

  return upstream
end

return {
  new = new,
}
