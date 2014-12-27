-- Copyright (C) Mashape, Inc.

local _M = {}

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

  local current_usage = dao.metrics:find_one({
    api_id = ngx.ctx.api.id,
    application_id = authenticated_entity_id,
    name = "requests." .. period,
    timestamp = timestamps[period]
  })

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
                                authenticated_entity_id,
                                "requests." .. k,
                                v, 1)
  end

end

return _M
