local singletons = require "kong.singletons"
local cache = require "kong.tools.database_cache"
local dns_client = require "dns.client"  -- due to startup/require order, cannot use the one from 'singletons' here
local toip = dns_client.toip

--===========================================================
-- Balancer based resolution
--===========================================================
local balancers = {}  -- table holding our balancer objects, indexed by upstream name

local function load_upstreams_into_memory()
  local upstreams, err = singletons.dao.upstreams:find_all()
  if err then
    return nil, err
  end
  
  -- build a dictionary, indexed by the upstreams name
  local upstream_dic = {}
  for _, up in ipairs(upstreams) do
    upstream_dic[up.name] = up
  end
  
  return upstream_dic
end

-- @param upstream_id Upstream uuid for which to load the target history
local function load_targets_into_memory(upstream_id)
  local target_history, err = singletons.dao.targets:find_all {upstream_id = upstream_id}
  if err then
    return nil, err
  end
  
  -- order by 'created_at'
  table.sort(target_history, function(a,b) return a.created_at<b.created_at end)

  return target_history
end

-- looks up a balancer for the target.
-- @param target the table with the target details
-- @return balancer if found, or nil if not found, or nil+error on error
local get_balancer = function(target)
  
  local upstreams_dic, err = cache.get_or_set(cache.upstreams_key(), load_upstreams_into_memory)
  if err then
    return nil, err
  end
  
  local upstream = upstreams_dic[target.upstream.host]
  if not upstream then
    return nil   -- there is no upstream by this name, so must be regular name, return and try dns 
  end
  
  local targets_history, err = cache.get_or_set(cache.targets_key(upstream.id), 
    function() 
      return load_targets_into_memory(upstream.id) 
    end
  )
  if err then
    return nil, err
  end

  local balancer = balancers[upstream.name]
  if not balancer then
    
-- TODO: create a new balancer
  
  elseif #balancer.targets_history ~= #targets_history or 
         balancer.target_history[#balancer.targets_history].created_at ~= target_history[#target_history].created_at then

-- TODO: target history has changed, go update balancer
  
  else
    -- found it
    return balancer
  end
end


local first_try_balancer = function(target)
end

local retry_balancer = function(target)
end

--===========================================================
-- simple DNS based resolution
--===========================================================

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


--===========================================================
-- Main entry point when resolving
--===========================================================

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
  load_upstreams_into_memory = load_upstreams_into_memory,  -- exported for test purposes
}