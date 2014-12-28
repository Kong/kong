-- Copyright (C) Mashape, Inc.

local _M = {}

local function set_header_limit_remaining(usage)
  ngx.header["X-RateLimit-Remaining"] = usage
end

function _M.execute(conf)
  local authenticated_entity_id = nil
  if ngx.ctx.authenticated_entity then
    authenticated_entity_id = ngx.ctx.authenticated_entity.id
  else
    authenticated_entity_id = ngx.var.remote_addr -- Use the IP if there is not authenticated entity
  end

  local period = conf.period
  local limit = conf.limit

  local timestamps = utils.get_timestamps(ngx.now())

  local current_usage = dao.metrics:find_one(ngx.ctx.api.id,
                                            authenticated_entity_id,
                                            "requests." .. period,
                                            timestamps[period])

  if current_usage then current_usage = current_usage.value else current_usage = 0 end

  ngx.header["X-RateLimit-Limit"] = limit
  if current_usage >= limit then
    set_header_limit_remaining(limit - current_usage)
    utils.show_error(429, "API rate limit exceeded")
  else
    set_header_limit_remaining(limit - current_usage - 1)
  end

  -- Increment usage for all the metrics
  -- TODO: this could also be done asynchronously in a timer maybe if specified in the conf (more performance, less security)?
  for k,v in pairs(timestamps) do
    dao.metrics:increment_metric(ngx.ctx.api.id,
                                authenticated_entity_id,
                                "requests." .. k,
                                v, 1)
  end

end

return _M
