local _M = {}

_M.STRATEGY_TYPES = {
    "memory",
}

-- strategies that store cache data only on the node, instead of
-- cluster-wide. this is typically used to handle purge notifications
_M.LOCAL_DATA_STRATEGIES = {
    memory = true,
    [1]    = "memory",
}

local function require_strategy(name)
    return require("kong.plugins.gql-proxy-cache.strategies." .. name)
end

return setmetatable(_M, {
    __call = function(_, opts)
        return require_strategy(opts.strategy_name).new(opts.strategy_opts)
    end
})
