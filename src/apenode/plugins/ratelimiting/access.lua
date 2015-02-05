-- Copyright (C) Mashape, Inc.

local Metric = nil

local kMetricName = "requests"

local function set_header_limit_remaining(usage)
  ngx.header["X-RateLimit-Remaining"] = usage
end

local _M = {}

function _M.execute(conf)
  local application_id
  local ip_address

  if ngx.ctx.authenticated_entity then
    application_id = ngx.ctx.authenticated_entity.id
  else
    ip_address = ngx.var.remote_addr
  end

  local period = conf.period
  local limit = conf.limit

  local timestamps = utils.get_timestamps(ngx.now())
  local usage_metric, err = Metric.find_one({ api_id = ngx.ctx.api.id,
                                              application_id = application_id,
                                              origin_ip = ip_address,
                                              name = kMetricName,
                                              period = period,
                                              timestamp = timestamps[period] }, dao)
  if err then
    ngx.log(ngx.ERROR, err)
  end

  local current_usage = 0
  if usage_metric then
    current_usage = usage_metric.value
  end

  ngx.header["X-RateLimit-Limit"] = limit
  if current_usage >= limit then
    set_header_limit_remaining(limit - current_usage)
    utils.show_error(429, "API rate limit exceeded")
  else
    set_header_limit_remaining(limit - current_usage - 1)
  end

  -- Increment metric
  local _, err = Metric.increment(ngx.ctx.api.id, application_id, ip_address, kMetricName, 1, dao)
  if err then
    ngx.log(ngx.ERROR, err)
  end
end

return _M
