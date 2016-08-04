local policies = require "kong.plugins.rate-limiting.policies"
local singletons = require "kong.singletons"

local ngx_log = ngx.log

local get_local_key = function(api_id, identifier, period_date, period)
  return string.format("ratelimit:%s:%s:%s:%s", api_id, identifier, period_date, period)
end

return {
  ["local"] = {
    increment = function(conf, api_id, identifier, current_timestamp, value, name)
      -- TODO
    end,
    usage = function(conf, api_id, identifier, current_timestamp, period, name)
      return policies["local"].usage(conf, api_id, identifier, current_timestamp, name.."_"..period)
    end
  },  
  ["cluster"] = {
    increment = function(conf, api_id, identifier, current_timestamp, value, name)
      local _, stmt_err = singletons.dao.response_ratelimiting_metrics:increment(api_id, identifier, current_timestamp, value, name)
      if stmt_err then
        ngx_log(ngx.ERR, tostring(stmt_err))
      end
    end,
    usage = function(conf, api_id, identifier, current_timestamp, period, name)
      local current_metric, err = singletons.dao.response_ratelimiting_metrics:find(api_id, identifier, current_timestamp, period, name)
      if err then
        return nil, err
      end
      return current_metric and current_metric.value or 0
    end
  },
  ["redis"] = {
    increment = function(conf, api_id, identifier, current_timestamp, value, name)

    end,
    usage = function(conf, api_id, identifier, current_timestamp, period, name)
      return policies["redis"].usage(conf, api_id, identifier, current_timestamp, name.."_"..period)
    end
  }
}