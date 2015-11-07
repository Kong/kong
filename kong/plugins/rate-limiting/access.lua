local constants = require "kong.constants"
local timestamp = require "kong.tools.timestamp"
local responses = require "kong.tools.responses"

local _M = {}

local function get_identifier()
  local identifier

  -- Consumer is identified by ip address or authenticated_credential id
  if ngx.ctx.authenticated_credential then
    identifier = ngx.ctx.authenticated_credential.id
  else
    identifier = ngx.var.remote_addr
  end

  return identifier
end

local function increment(api_id, identifier, current_timestamp, value)
  -- Increment metrics for all periods if the request goes through
  local _, stmt_err = dao.ratelimiting_metrics:increment(api_id, identifier, current_timestamp, value)
  if stmt_err then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(stmt_err)
  end
end

local function get_usage(api_id, identifier, current_timestamp, limits)
  local usage = {}
  local stop

  for name, limit in pairs(limits) do
    local current_metric, err = dao.ratelimiting_metrics:find_one(api_id, identifier, current_timestamp, name)
    if err then
      return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
    end

    -- What is the current usage for the configured limit name?
    local current_usage = current_metric and current_metric.value or 0
    local remaining = limit - current_usage

    -- Recording usage
    usage[name] = {
      limit = limit,
      remaining = remaining
    }

    if remaining <= 0 then
      stop = name
    end
  end

  return usage, stop
end

function _M.execute(conf)
  local current_timestamp = timestamp.get_utc()

  -- Consumer is identified by ip address or authenticated_credential id
  local identifier = get_identifier()

  local api_id = ngx.ctx.api.id

  -- Load current metric for configured period
  local usage, stop = get_usage(api_id, identifier, current_timestamp, conf)

  -- Adding headers
  for k, v in pairs(usage) do
    ngx.header[constants.HEADERS.RATELIMIT_LIMIT.."-"..k] = v.limit
    ngx.header[constants.HEADERS.RATELIMIT_REMAINING.."-"..k] = math.max(0, (stop == nil or stop == k) and v.remaining - 1 or v.remaining) -- -increment_value for this current request
  end

  -- If limit is exceeded, terminate the request
  if stop then
    return responses.send(429, "API rate limit exceeded")
  end

  -- Increment metrics for all periods if the request goes through
  increment(api_id, identifier, current_timestamp, 1)
end

return _M
