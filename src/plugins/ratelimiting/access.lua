local constants = require "kong.constants"
local timestamp = require "kong.tools.timestamp"

local _M = {}

function _M.execute(conf)
  local current_timestamp = timestamp.get_utc()

  -- Compute is identifier is by ip address or authenticated entity id
  local identifier
  if ngx.ctx.authenticated_entity then
    identifier = ngx.ctx.authenticated_entity.id
  else
    identifier = ngx.var.remote_addr
  end

  -- Load current metric for configured period
  local current_metric, err = dao.ratelimiting_metrics:find_one(ngx.ctx.api.id, identifier, current_timestamp, conf.period)
  if err then
    ngx.log(ngx.ERR, err)
    utils.show_error(500)
  end

  -- What is the current usage for the configured period?
  local current_usage
  if current_metric ~= nil then
    current_usage = current_metric.value
  else
    current_usage = 0
  end

  local remaining = conf.limit - current_usage
  ngx.header[constants.HEADERS.RATELIMIT_LIMIT] = conf.limit
  ngx.header[constants.HEADERS.RATELIMIT_REMAINING] = math.max(0, remaining - 1) -- -1 for this current request

  if remaining == 0 then
    utils.show_error(429, "API rate limit exceeded")
  end

  -- Increment metrics for all periods if the request goes through
  local _, stmt_err = dao.ratelimiting_metrics:increment(ngx.ctx.api.id, identifier, current_timestamp)
  if stmt_err then
    ngx.log(ngx.ERR, stmt_err)
    utils.show_error(500)
  end
end

return _M
