local ip = require "resty.mediador.ip"
local px = require "resty.mediador.proxy"


local function trust_all()  return true  end
local function trust_none() return false end


local _M = { valid = ip.valid }


function _M.init(config)
  local ips = config.trusted_ips
  local count = #ips
  local trusted_ips = {}
  local trust_all_ipv4, trust_all_ipv6

  -- This is because we don't support unix: that the ngx_http_realip module supports.
  -- Also as an optimization we will only compile trusted ips if the Kong is not run
  -- with the default 0.0.0.0/0, ::/0 aka trust all ip addresses settings.
  for i = 1, count do
    local address = ips[i]

    if ip.valid(address) then
      trusted_ips[#trusted_ips+1] = address
      if address == "0.0.0.0/0" then
        trust_all_ipv4 = true

      elseif address == "::/0" then
        trust_all_ipv6 = true
      end
    end
  end

  if #trusted_ips == 0 then
    return {
      valid   = ip.valid,
      trusted = trust_none,
    }
  end

  if trust_all_ipv4 and trust_all_ipv6 then
    return {
      valid   = ip.valid,
      trusted = trust_all,
    }
  end

  return {
    valid   = ip.valid,
    trusted = px.compile(trusted_ips),
  }
end


return _M
