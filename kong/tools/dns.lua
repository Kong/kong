local dns_client = require "dns.client"

local initialized = false

--- Load and setup the DNS client according to the provided configuration.
-- @param conf (table) Kong configuration
-- @return 
local setup_client = function(conf)
  assert(not initialized, "DNS client was already initialized")
  conf = conf or {}
  local hosts = conf.dns_hostsfile      -- filename
  local servers = conf.dns_resolver     -- array with ipv4[:port] entries
  
  -- servers must be reformatted as name/port sub-arrays
  if servers then
    for i, server in ipairs(servers) do
      local ip, port = server:match("^([^:]+)%:*(%d*)$")
      servers[i] = { ip, tonumber(port) or 53 }
    end
  end
    
  local opts = {
    hosts = hosts,
    resolv_conf = nil,
    max_resolvers = 50,
    nameservers = servers,
    retrans = 5,
    timeout = 2000,
    no_recurse = false,
  }
  
  assert(dns_client.init(opts))
  initialized = true
  
  return dns_client
end

return setup_client
