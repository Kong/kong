---
-- Trusted IPs module
--
-- This module can be used to determine whether or not a given IP address is
-- in the range of trusted IP addresses defined by the `trusted_ips` configuration
-- property.
--
-- Trusted IP addresses are those that are known to send correct replacement
-- addresses for clients (as per the chosen header field, e.g. X-Forwarded-*).
--
-- See [docs.konghq.com/latest/configuration/#trusted_ips](https://docs.konghq.com/latest/configuration/#trusted_ips)
--
-- @module kong.ip
local ip = require "resty.mediador.ip"

---
-- Depending on the `trusted_ips` configuration property,
-- this function will return whether a given ip is trusted or not
--
-- Both ipv4 and ipv6 are supported.
--
-- @function kong.ip.is_trusted
-- @phases init_worker, certificate, rewrite, access, header_filter, body_filter, log
-- @tparam string address A string representing an IP address
-- @treturn boolean `true` if the IP is trusted, `false` otherwise
-- @usage
-- if kong.ip.is_trusted("1.1.1.1") then
--   kong.log("The IP is trusted")
-- end

local function new(self)
  local _IP = {}

  local ips = self.configuration.trusted_ips or {}
  local n_ips = #ips
  local trusted_ips = self.table.new(n_ips, 0)
  local trust_all_ipv4
  local trust_all_ipv6

  -- This is because we don't support unix: that the ngx_http_realip module
  -- supports.  Also as an optimization we will only compile trusted ips if
  -- Kong is not run with the default 0.0.0.0/0, ::/0 aka trust all ip
  -- addresses settings.
  local idx = 1
  for i = 1, n_ips do
    local address = ips[i]

    if ip.valid(address) then
      trusted_ips[idx] = address
      idx = idx + 1

      if address == "0.0.0.0/0" then
        trust_all_ipv4 = true

      elseif address == "::/0" then
        trust_all_ipv6 = true
      end
    end
  end

  if #trusted_ips == 0 then
    _IP.is_trusted = function() return false end

  elseif trust_all_ipv4 and trust_all_ipv6 then
    _IP.is_trusted = function() return true end

  else
    -- do not load if not needed
    local px = require "resty.mediador.proxy"

    _IP.is_trusted = px.compile(trusted_ips)
  end

  return _IP
end


return {
  new = new,
}
