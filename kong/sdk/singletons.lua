-- The singletons namespace contains instances of objects that are:
--  1. considered singletons
--  2. need the kong configuration to be instantiated


local function new(sdk)
  local initializers = {
    ip = true,
  }

  local initialized = {}


  do
    -- kong.ip module, whose main purpose is to verify whether a given IP
    -- address belongs to the range of the trusted_ips setting.
    local ip = require "resty.mediador.ip"
    local base = require "kong.sdk.utils.base"


    function initializers.ip(kong_config)
      local ips = kong_config.trusted_ips or {}
      local n_ips = #ips
      local trusted_ips = base.new_tab(n_ips, 0)
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
        return {
          is_trusted = function()
                         return false
                       end,
        }
      end

      if trust_all_ipv4 and trust_all_ipv6 then
        return {
          is_trusted = function()
                         return true
                       end,
        }
      end

      -- do not load if not needed
      local px = require "resty.mediador.proxy"

      return {
        is_trusted = px.compile(trusted_ips),
      }
    end
  end


  function sdk.init(kong_config, ...)
    kong_config = kong_config or {}

    local to_init = { ... }

    for _, singleton_name in ipairs(to_init) do
      if type(initializers[singleton_name]) ~= "function" then
        error("no such singleton to initialize: " .. singleton_name, 2)
      end

      if initialized[singleton_name] then
        error("singleton already initialized or conflicting: " .. singleton_name, 2)
      end

      local singleton = initializers[singleton_name](kong_config)
      if not singleton then
        error(singleton_name .. " singleton initializer returned nil")
      end

      sdk[singleton_name] = singleton
      initialized[singleton_name] = true
    end

    return true
  end


  function sdk.get_singletons()
    local map = {}

    for name in pairs(initializers) do
      map[name] = true
    end

    return map
  end
end


return {
  new = new,
}
