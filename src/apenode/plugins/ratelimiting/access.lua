-- Copyright (C) Mashape, Inc.

local Metric = require "apenode.models.metric"

local _M = {}

local REQUESTS = "requests"

local function set_header_limit_remaining(usage)
  ngx.header["X-RateLimit-Remaining"] = usage
end

function _M.execute(conf)
  local authenticated_entity_id
  local ip_address

  if ngx.ctx.authenticated_entity then
    authenticated_entity_id = ngx.ctx.authenticated_entity.id
  else
    ip_address = ngx.var.remote_addr
  end

  local period = conf.period
  local limit = conf.limit

  local timestamps = utils.get_timestamps(ngx.now())

  local current_usage = Metric.find_one({ api_id = ngx.ctx.api.id,
                                          application_id = authenticated_entity_id,
                                          origin_ip = ip_address,
                                          name = REQUESTS,
                                          period = period,
                                          timestamp = timestamps[period] }, dao)

  if current_usage then current_usage = current_usage.value else current_usage = 0 end

  ngx.header["X-RateLimit-Limit"] = limit
  if current_usage >= limit then
    set_header_limit_remaining(limit - current_usage)
    utils.show_error(429, "API rate limit exceeded")
  else
    set_header_limit_remaining(limit - current_usage - 1)
  end

  -- Increment metric
  Metric.increment(ngx.ctx.api.id, authenticated_entity_id, ip_address, REQUESTS, 1, dao)
end

return _M
