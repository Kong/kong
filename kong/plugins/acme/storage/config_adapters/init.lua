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
