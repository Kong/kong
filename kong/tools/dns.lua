local dns_client

--- Load and setup the DNS client according to the provided configuration.
-- Will clear the cache if called multiple times.
-- @param conf (table) Kong configuration
-- @return the initialized `dns.client` module, or nil+error if it was already initialized
local setup_client = function(conf)
  if not dns_client then 
    dns_client = require "dns.client"
  end

  conf = conf or {}
  local hosts = conf.dns_hostsfile      -- filename
  local servers = {}
  
  -- servers must be reformatted as name/port sub-arrays
  if conf.dns_resolver then
    for i, server in ipairs(conf.dns_resolver) do
      local ip, port = server:match("^([^:]+)%:*(%d*)$")
      servers[i] = { ip, tonumber(port) or 53 }   -- inserting port if omitted
    end
  end
    
  local opts = {
    hosts = hosts,
    resolv_conf = nil,
    nameservers = servers,
    retrans = 5,
    timeout = 2000,
    no_recurse = false,
  }
  
  assert(dns_client.init(opts))

  return dns_client
end

return setup_client
