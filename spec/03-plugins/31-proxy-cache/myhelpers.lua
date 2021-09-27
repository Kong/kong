local helpers = require "spec.helpers"
local strategies = require("kong.plugins.proxy-cache.strategies")

local TIMEOUT = 10 -- default timeout for non-memory strategies

-- use wait_until spec helper only on async strategies
local function wait_until(policy, func)
  if strategies.DELAY_STRATEGY_STORE[policy] then
    helpers.wait_until(func, TIMEOUT)
  end
end

local function wait_appear(policy, strategy, cache_key)
    wait_until(policy, function()
        return strategy:fetch(cache_key) ~= nil
    end)
end

local function wait_disappear(policy, strategy, cache_key)
    wait_until(policy, function()
        return strategy:fetch(cache_key) == nil
    end)
end

----------
-- Exposed
----------
-- @export
return {
  wait_appear = wait_appear,
  wait_disappear = wait_disappear,
  wait_until  = wait_until,
  timeout = TIMEOUT,
}
