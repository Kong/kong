-- Copyright (C) Kong Inc.
local timestamp = require "kong.tools.timestamp"
local policies = require "kong.plugins.rate-limiting.policies"


local kong = kong
local ngx = ngx
local max = math.max
local time = ngx.time
local floor = math.floor
local pairs = pairs
local tostring = tostring
local timer_at = ngx.timer.at


local EMPTY = {}
local EXPIRATIONS = policies.EXPIRATIONS


local RATELIMIT_LIMIT     = "RateLimit-Limit"
local RATELIMIT_REMAINING = "RateLimit-Remaining"
local RATELIMIT_RESET     = "RateLimit-Reset"
local RETRY_AFTER         = "Retry-After"


local X_RATELIMIT_LIMIT = {
  second = "X-RateLimit-Limit-Second",
  minute = "X-RateLimit-Limit-Minute",
  hour   = "X-RateLimit-Limit-Hour",
  day    = "X-RateLimit-Limit-Day",
  month  = "X-RateLimit-Limit-Month",
  year   = "X-RateLimit-Limit-Year",
}

local X_RATELIMIT_REMAINING = {
  second = "X-RateLimit-Remaining-Second",
  minute = "X-RateLimit-Remaining-Minute",
  hour   = "X-RateLimit-Remaining-Hour",
  day    = "X-RateLimit-Remaining-Day",
  month  = "X-RateLimit-Remaining-Month",
  year   = "X-RateLimit-Remaining-Year",
}


local RateLimitingHandler = {}


RateLimitingHandler.PRIORITY = 901
RateLimitingHandler.VERSION = "2.1.0"


local function get_identifier(conf)
  local identifier

  if conf.limit_by == "service" then
    identifier = ""
  elseif conf.limit_by == "consumer" then
    identifier = (kong.client.get_consumer() or
                  kong.client.get_credential() or
                  EMPTY).id

  elseif conf.limit_by == "credential" then
    identifier = (kong.client.get_credential() or
                  EMPTY).id
  end

  return identifier or kong.client.get_forwarded_ip()
end


local function get_usage(conf, identifier, current_timestamp, limits)
  local usage = {}
  local stop

  for period, limit in pairs(limits) do
    local current_usage, err = policies[conf.policy].usage(conf, identifier, period, current_timestamp)
    if err then
      return nil, nil, err
    end

    -- What is the current usage for the configured limit name?
    local remaining = limit - current_usage

    -- Recording usage
    usage[period] = {
      limit = limit,
      remaining = remaining,
    }

    if remaining <= 0 then
      stop = period
    end
  end

  return usage, stop
end


local function increment(premature, conf, ...)
  if premature then
    return
  end

  policies[conf.policy].increment(conf, ...)
end


function RateLimitingHandler:access(conf)
  local current_timestamp = time() * 1000

  -- Consumer is identified by ip address or authenticated_credential id
  local identifier = get_identifier(conf)
  local fault_tolerant = conf.fault_tolerant

  -- Load current metric for configured period
  local limits = {
    second = conf.second,
    minute = conf.minute,
    hour = conf.hour,
    day = conf.day,
    month = conf.month,
    year = conf.year,
  }

  local usage, stop, err = get_usage(conf, identifier, current_timestamp, limits)
  if err then
    if fault_tolerant then
      kong.log.err("failed to get usage: ", tostring(err))
    else
      kong.log.err(err)
      return kong.response.exit(500, { message = "An unexpected error occurred" })
    end
  end

  if usage then
    -- Adding headers
    local reset
    if not conf.hide_client_headers then
      local headers = {}
      local timestamps
      local limit
      local window
      local remaining
      for k, v in pairs(usage) do
        local current_limit = v.limit
        local current_window = EXPIRATIONS[k]
        local current_remaining = v.remaining
        if stop == nil or stop == k then
          current_remaining = current_remaining - 1
        end
        current_remaining = max(0, current_remaining)

        if not limit or (current_remaining < remaining)
                     or (current_remaining == remaining and
                         current_window > window)
        then
          limit = current_limit
          window = current_window
          remaining = current_remaining

          if not timestamps then
            timestamps = timestamp.get_timestamps(current_timestamp)
          end

          reset = max(1, window - floor((current_timestamp - timestamps[k]) / 1000))
        end

        headers[X_RATELIMIT_LIMIT[k]] = current_limit
        headers[X_RATELIMIT_REMAINING[k]] = current_remaining
      end

      headers[RATELIMIT_LIMIT] = limit
      headers[RATELIMIT_REMAINING] = remaining
      headers[RATELIMIT_RESET] = reset

      kong.ctx.plugin.headers = headers
    end

    -- If limit is exceeded, terminate the request
    if stop then
      return kong.response.exit(429, { message = "API rate limit exceeded" }, {
        [RETRY_AFTER] = reset
      })
    end
  end

  kong.ctx.plugin.timer = function()
    local ok, err = timer_at(0, increment, conf, limits, identifier, current_timestamp, 1)
    if not ok then
      kong.log.err("failed to create timer: ", err)
    end
  end
end


function RateLimitingHandler:header_filter(_)
  local headers = kong.ctx.plugin.headers
  if headers then
    kong.response.set_headers(headers)
  end
end


function RateLimitingHandler:log(_)
  if kong.ctx.plugin.timer then
    kong.ctx.plugin.timer()
  end
end


return RateLimitingHandler
