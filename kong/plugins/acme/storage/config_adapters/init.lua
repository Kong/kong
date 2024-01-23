-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local redis_config_adapter = require "kong.plugins.acme.storage.config_adapters.redis"

local function load_adapters()
    local adapters_mapping = {
        redis = redis_config_adapter
    }

    local function identity(config)
        return config
    end

    local default_value_mt = { __index = function() return identity  end }

    setmetatable(adapters_mapping, default_value_mt)

    return adapters_mapping
end

local adapters = load_adapters()

local function adapt_config(storage_type, storage_config)
    local adapter_fn = adapters[storage_type]
    return adapter_fn(storage_config[storage_type])
end

return {
    adapt_config = adapt_config
}
