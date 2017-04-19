local dns_client

--- Load and setup the DNS client according to the provided configuration.
-- @param conf (table) Kong configuration
-- @return the initialized `resty.dns.client` module, or an error
local setup_client = function(conf)
  if not dns_client then 
    dns_client = require "resty.dns.client"
  end

  conf = conf or {}
  local servers = {}
  
  -- servers must be reformatted as name/port sub-arrays
  if conf.dns_resolver then
    for i, server in ipairs(conf.dns_resolver) do
      local ip, port = server:match("^([^:]+)%:*(%d*)$")
      servers[i] = { ip, tonumber(port) or 53 }   -- inserting port if omitted
    end
  end
    
  local opts = {
    hosts = conf.dns_hostsfile,
    resolvConf = nil,                -- defaults to system resolv.conf
    nameservers = servers,           -- provided list or taken from resolv.conf
    retrans = nil,                   -- taken from system resolv.conf; attempts
    timeout = nil,                   -- taken from system resolv.conf; timeout
    badTtl = conf.dns_not_found_ttl, -- ttl in seconds for dns error responses (except 3 - name error)
    emptyTtl = conf.dns_error_ttl,   -- ttl in seconds for empty and "(3) name error" dns responses
    order = conf.dns_order,          -- order of trying record types
  }
  
  assert(dns_client.init(opts))

  return dns_client
end

return setup_client
