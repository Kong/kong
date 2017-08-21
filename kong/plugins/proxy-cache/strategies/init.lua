local _M = {}

local function require_strategy(name)
  return require("kong.plugins.proxy-cache.strategies." .. name)
end

return setmetatable(_M, {
  __call = function(opts)
    return require_strategy(opts.strategy_name).new(opts.strategy_opts)
  end
})
