-- Copyright (C) Mashape, Inc.

local _M = {}

function _M.execute()
  local period = configuration.plugins.ratelimiting.period
  local limit = configuration.plugins.ratelimiting.limit

  local timestamps = utils.get_timestamps(ngx.now())
  local current_usage = dao.metrics:retrieve_metric(ngx.ctx.api.id,
                                                    ngx.ctx.authenticated_entity.id,
                                                    "requests." .. period,
                                                    timestamps[period])

  if current_usage then current_usage = current_usage.value else current_usage = 0 end

  ngx.header["X-RateLimit-Limit"] = limit
  ngx.header["X-RateLimit-Remaining"] = limit - current_usage

  if current_usage >= limit then
    utils.show_error(429, "API rate limit exceeded")
  end

  -- Increment usage for all the metrics
  -- TODO: this could also be done asynchronously in a timer maybe if specified in the conf (more performance, less security)?
  for k,v in pairs(timestamps) do
    dao.metrics:increment_metric(ngx.ctx.api.id,
                                ngx.ctx.authenticated_entity.id,
                                "requests." .. k,
                                v, 1)
  end

end

return _M
