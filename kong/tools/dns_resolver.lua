local Object = require "classic"
local stringy = require "stringy"
local cache = require "kong.tools.database_cache"
local resolver = require "resty.dns.resolver"

local DEFAULT_TIMEOUT = 2000
local DEFAULT_ATTEMPTS = 5

local DnsResolver = Object:extend()

function DnsResolver:new(host, port, timeout, attempts)
  self.host = host
  self.port = port
  self.timeout = timeout or DEFAULT_TIMEOUT
  self.attempts = attempts or DEFAULT_ATTEMPTS
end

function DnsResolver:query(address, type)
  -- Init the resolver
  local r, err = resolver:new{
    nameservers = {{self.host, self.port}},
    retrans = self.attempts,
    timeout = self.timeout
  }
  if not r then
    return nil, "Startup error: "..err
  end

  -- Make query
  local answers, err = r:query(address, {qtype = r["TYPE_"..type]})
  if not answers then
    return nil, "failed to query the DNS server: ", err
  end

  if answers.errcode then
    return nil, "server returned error code: ", answers.errcode, ": ", answers.errstr
  end

  return answers
end

function DnsResolver:resolve(address, port, enable_srv)
  -- Retrieve from cache
  local cache_key = cache.dns_key(address)
  local result = cache.get(cache_key)
  if result then
    return {host = result.host, port = result.port}
  end

  -- Query for A record
  local answers, err = self:query(address, "A")
  if err then
    return nil, err
  end
  if #answers <= 0 then
    return nil, "could not find any record for "..address
  end

  local a_answer = answers[1]
  local final_address = a_answer.address

  -- Query for SRV record
  local final_port = port
  if enable_srv then
    local answers, err = self:query(address, "SRV")
    if not err and #answers > 0 then -- Ignore the error because some DNS servers don't support SRV
      local srv_answer = answers[1]
      if srv_answer.port > 0 then
        final_port = srv_answer.port
      end
    end
  end

  if a_answer.ttl > 0 then
    cache.set(cache_key, {host = final_address, port = final_port}, a_answer.ttl)
  end

  return {host=final_address, port=final_port}
end

return DnsResolver