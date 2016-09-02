local dns_client

--- Load and setup the DNS client according to the provided configuration.
-- @param conf (table) Kong configuration
-- @return the initialized `dns.client` module, or nil+error if it was already initialized
local setup_client = function(conf)
  if dns_client then
    return nil, "DNS client already initialized"
  else
    dns_client = require "dns.client"
  end

  conf = conf or {}
  local hosts = conf.dns_hostsfile      -- filename
  local servers = conf.dns_resolver     -- array with ipv4[:port] entries
  
  -- servers must be reformatted as name/port sub-arrays
  if servers then
    for i, server in ipairs(servers) do
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
