local dns_client = require "resty.dns.client"

local toip = dns_client.toip

-- looks up a balancer for the target.
-- @param target the table with the target details
-- @return balancer if found, or nil if not found, or nil+error on error
local get_balancer = function(target)
  return nil  -- TODO: place holder, forces dns use to first fix regression
end


local first_try_balancer = function(target)
end

local retry_balancer = function(target)
end

local first_try_dns = function(target)
  local ip, port = toip(target.upstream.host, target.upstream.port, false)
  if not ip then
    return nil, port
  end
  target.ip = ip
  target.port = port
  return true
end

local retry_dns = function(target)
  local ip, port = toip(target.upstream.host, target.upstream.port, true)
  if type(ip) ~= "string" then
    return nil, port
  end
  target.ip = ip
  target.port = port
  return true
end


-- Resolves the target structure in-place (fields `ip` and `port`).
--
-- If the hostname matches an 'upstream' pool, then it must be balanced in that 
-- pool, in this case any port number provided will be ignored, as the pool provides it.
--
-- @param target the data structure as defined in `core.access.before` where it is created
-- @return true on success, nil+error otherwise
local function execute(target)
  if target.type ~= "name" then
    -- it's an ip address (v4 or v6), so nothing we can do...
    target.ip = target.upstream.host
    target.port = target.upstream.port or 80
    return true
  end
  
  -- when tries == 0 it runs before the `balancer` context (in the `access` context),
  -- when tries >= 2 then it performs a retry in the `balancer` context
  if target.tries == 0 then
    local err
    -- first try, so try and find a matching balancer/upstream object
    target.balancer, err = get_balancer(target)
    if err then return nil, err end

    if target.balancer then
      return first_try_balancer(target)
    else
      return first_try_dns(target)
    end
  else
    if target.balancer then
      return retry_balancer(target)
    else
      return retry_dns(target)
    end
  end
end

return { 
  execute = execute,
}