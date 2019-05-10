local policies = require "kong.plugins.response-ratelimiting.policies"
local pairs = pairs


local _M = {}


local function log(premature, conf, identifier, current_timestamp, increments, usage)
  if premature then
    return
  end

  -- Increment metrics for all periods if the request goes through
  for k in pairs(usage) do
    if increments[k] and increments[k] ~= 0 then
      policies[conf.policy].increment(conf, identifier, k, current_timestamp, increments[k])
    end
  end
end


function _M.execute(conf, identifier, current_timestamp, increments, usage)
  local ok, err = ngx.timer.at(0, log, conf, identifier, current_timestamp, increments, usage)
  if not ok then
    kong.log.err("failed to create timer: ", err)
  end
end


return _M
