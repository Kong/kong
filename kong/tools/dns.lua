local dns_client

--- Load and setup the DNS client according to the provided configuration.
-- @param conf (table) Kong configuration
-- @return the initialized `dns.client` module, or an error
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
    resolv_conf = nil,     -- defaults to system resolv.conf
    nameservers = servers, -- provided list or taken from resolv.conf
    retrans = nil,         -- taken from system resolv.conf; attempts
    timeout = nil,         -- taken from system resolv.conf; timeout
    bad_ttl = nil,         -- ttl in seconds for bad dns responses (empty/error)
  }
  
  assert(dns_client.init(opts))

  return dns_client
end

return setup_client
