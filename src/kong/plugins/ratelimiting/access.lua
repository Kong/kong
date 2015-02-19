local _M = {}

function _M.execute(conf)
  local current_timestamp = utils.get_utc()

  -- Compute is identifier is by ip address or application id
  local identifier

  local inspect = require "inspect"
  print(inspect(ngx.ctx.authenticated_entity))
  print(inspect(conf))

  if ngx.ctx.authenticated_entity then
    identifier = ngx.ctx.authenticated_entity.id
  else
    identifier = ngx.var.remote_addr
  end

  -- Load current metric for configured period
  local current_metric, err = dao.metrics:find_one(ngx.ctx.api.id, identifier, current_timestamp, conf.period)
  if err then
    ngx.log(ngx.ERROR, err)
  end

  -- What is the current usage for the configured period?
  local current_usage
  if current_metric ~= nil then
    current_usage = current_metric.value
  else
    current_usage = 0
  end

  local remaining = conf.limit - current_usage
  print("remaining for entity: "..identifier.." : "..remaining)
  ngx.header["X-RateLimit-Limit"] = conf.limit
  ngx.header["X-RateLimit-Remaining"] = math.max(0, remaining - 1) -- -1 for this current request

  if remaining == 0 then
    utils.show_error(429, "API rate limit exceeded")
  end

  -- Increment metrics for all periods if the request goes through
  local _, err = dao.metrics:increment(ngx.ctx.api.id, identifier, current_timestamp)
  if err then
    ngx.log(ngx.ERROR, err)
  end
end

return _M
