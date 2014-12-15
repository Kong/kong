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

  ngx.header["X-RateLimit-Limit"] = limit
  ngx.header["X-RateLimit-Remaining"] = limit - (current_usage + 1)

  if current_usage >= limit then
    utils.show_error(429, "API rate limit exceeded")
  end

  -- Increment usage for all the metrics
  for k,v in pairs(timestamps) do
    dao.metrics:increment_metric(ngx.ctx.api.id,
                                ngx.ctx.authenticated_entity.id,
                                "requests." .. period,
                                timestamps[period], 1)
  end

end

return _M
