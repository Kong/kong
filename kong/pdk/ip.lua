local ip = require "resty.mediador.ip"


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
  for i = 1, n_ips do
    local address = ips[i]

    if ip.valid(address) then
      table.insert(trusted_ips, address)

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
