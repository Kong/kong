local utils = require "kong.tools.utils"
local dns_client = require "dns.client"


-- Wrapper for dns functions, handles the errors.
-- Will not return on client errors (returned as http errorcodes)
-- incoming nil+error will be passed through.
-- @return valid record with at least 1 entry, or nil + error
local handle_dns_error = function(rec, err)
  if not rec then
    return rec, err
  elseif rec.errcode then
    -- TODO: proper dns server error, what http errors to return???
    ngx.log(ngx.ERR, "dns server error")
    return ngx.exit(500)
  elseif #rec == 0 then
    -- TODO: proper dns server error, what http error to return???
    ngx.log(ngx.ERR, "no dns entries found")
    return ngx.exit(500)
  end
  return rec
end

-- looks up a balancer for the target.
-- @param target the table with the target details
-- @return balancer if found, or nil if not found, or nil+error on error
local get_balancer = function(target)
  return nil  -- TODO: place holder, forces dns use to first fix regression
end


local first_try_balancer = function(target)
end

-- NOTE: retry runs in the limited `BALANCER` context
local retry_balancer = function(target)
end

-- tracks the pointer for retries
-- resolves any SRV targets if necessary
-- @return true (with ip and port fields set) or nil+error
local get_ip = function(target, dns_cache_only)
  
-- TODO: make dns_pointer a table with pointers indexed by their dns record list
-- reduces code duplication below and handles pointer on deeper levels

  local list = target.dns_record
  local p = target.dns_pointer
  if not p then
    p = 1
  else
    p = p + 1
    if p > #list then   -- todo: for SRV handle priority field (lowest first), for now just round-robin
      p = 1
    end
  end
  target.dns_pointer = p
  local rec = list[p]
  
  -- we have the port by now
  target.port = rec.port or target.port  -- rec.port only exists for SRV records
  
  -- A and AAAA have an address field, whilst the SRV target field might be an IP address
  local ip = rec.address or (utils.hostname_type(rec.target) ~= "name" and rec.target)
  if ip then
    target.ip = ip
    return true
  end
  
  -- what's left now is an SRV with a named target.
  local i = 1
  local host = rec.target
  repeat
    local list, err = handle_dns_error(dns_client.resolve(host, dns_cache_only))
    if not list then
      return list, err
    end
    -- no more pointers traversing lists, just pick the first one, leave balancing 
    -- to dns server, as we're already 2 levels deep
    local rec = list[1]
    
    -- we have the port by now
    target.port = rec.port or target.port  -- rec.port only exists for SRV records
    
    -- A and AAAA have an address field, and the SRV target field might be an IP address
    local ip = rec.address or (utils.hostname_type(rec.target) ~= "name" and rec.target)
    if ip then
      target.ip = ip
      return true
    end
    -- still not found, next iteration
    host = rec.target
    i = i + 1
    
  until i == 10

  return nil, "dns recursion error, "..i.." levels"
end


local first_try_dns = function(target)
  local rec, err = handle_dns_error(dns_client.resolve(target.upstream.host))
  if not rec then
    return rec, err
  end
  -- store the top level dns result in the ctx structure for future use.
  -- Note: cname records will have been dereferenced by the dns lib, so
  -- we got A, AAAA or SRV.
  target.dns_record = rec

  return get_ip(target)  
end

-- NOTE: retry runs in the limited `BALANCER` context
local retry_dns = function(target)
  return get_ip(target, true)
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