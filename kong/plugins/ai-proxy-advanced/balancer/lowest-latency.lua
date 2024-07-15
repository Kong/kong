-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local ewma = require "kong.plugins.ai-proxy-advanced.balancer.ewma"

local algo = {}
algo.__index = algo

function algo:afterHostUpdate()
  return ewma.afterHostUpdate(self)
end


function algo:afterBalance(conf, target)
  -- get the latency as datapoint
  -- local data_point = TTFT + TPOT * ai_response_tokens
  local data_point = 0 -- blocked on latency metrics for now
  return ewma.afterBalance(self, target, data_point)
end


function algo:getPeer(...)
  return ewma.getPeer(self, ...)
end

function algo:cleanup()
  return ewma.cleanup(self)
end

function algo.new(targets)
  return setmetatable(ewma.new(targets), algo)
end

return algo