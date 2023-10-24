-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local kong = kong

local _M = {}

local SNI_CACHE_KEY = "tls-handshake-modifier:cert_enabled_snis"
_M.SNI_CACHE_KEY = SNI_CACHE_KEY

local function invalidate_sni_cache()
   kong.cache:invalidate(SNI_CACHE_KEY)
end

function _M.init_worker()
  if kong.configuration.database == "off" or not (kong.worker_events and kong.worker_events.register) then
    return
  end

  local worker_events = kong.worker_events
  if not worker_events or not worker_events.register then
    return
  end

  worker_events.register(function(data)
    if data.entity.name == "tls-handshake-modifier" then
      worker_events.post("tls-modifier-post", data.operation, data.entity.config)
    end
  end, "crud", "plugins")

  worker_events.register(function(data)
    invalidate_sni_cache()
  end, "crud", "routes")

  worker_events.register(function(data)
    invalidate_sni_cache()
  end, "crud", "services")

  worker_events.register(function(config)
    invalidate_sni_cache()
  end, "tls-modifier-post", "create")

  worker_events.register(function(config)
    invalidate_sni_cache()
  end, "tls-modifier-post", "delete")

  worker_events.register(function(config)
    invalidate_sni_cache()
  end, "tls-modifier-post", "update")

end

return _M
