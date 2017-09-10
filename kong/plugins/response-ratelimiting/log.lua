local policies = require "kong.plugins.response-ratelimiting.policies"
local pairs = pairs

local _M = {}

local function log(premature, conf, api_id, identifier, current_timestamp, increments, usage)
  if premature then
    return
  end
  
  -- Increment metrics for all periods if the request goes through
  for k, v in pairs(usage) do
    if increments[k] and increments[k] ~= 0 then
      policies[conf.policy].increment(conf, api_id, identifier, current_timestamp, increments[k], k)
    end
  end
end

function _M.execute(conf, api_id, identifier, current_timestamp, increments, usage)
  local ok, err = ngx.timer.at(0, log, conf, api_id, identifier, current_timestamp, increments, usage)
  if not ok then
    ngx.log(ngx.ERR, "failed to create timer: ", err)
  end
end

return _M
