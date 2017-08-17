-- Copyright (C) Mashape, Inc.

local policies = require "kong.plugins.rate-limiting.policies"
local timestamp = require "kong.tools.timestamp"
local responses = require "kong.tools.responses"
local BasePlugin = require "kong.plugins.base_plugin"
local luatz = require "luatz"

local floor = math.floor
local ngx_log = ngx.log
local pairs = pairs
local tostring = tostring
local ngx_timer_at = ngx.timer.at
local new_from_timestamp = luatz.timetable.new_from_timestamp

local RATELIMIT_LIMIT = "X-RateLimit-Limit"
local RATELIMIT_REMAINING = "X-RateLimit-Remaining"
local RATELIMIT_RESET = "X-RateLimit-Reset"

local RateLimitingHandler = BasePlugin:extend()

RateLimitingHandler.PRIORITY = 900

local function get_identifier(conf)
  local identifier

  -- Consumer is identified by ip address or authenticated_credential id
  if conf.limit_by == "consumer" then
    identifier = ngx.ctx.authenticated_consumer and ngx.ctx.authenticated_consumer.id
    if not identifier and ngx.ctx.authenticated_credential then -- Fallback on credential
      identifier = ngx.ctx.authenticated_credential.id
    end
  elseif conf.limit_by == "credential" then
    identifier = ngx.ctx.authenticated_credential and ngx.ctx.authenticated_credential.id
  end

  if not identifier then
    identifier = ngx.var.remote_addr
  end

  return identifier
end

local function get_usage(conf, api_id, identifier, current_timestamp, limits)
  local usage = {}
  local stop

  for name, limit in pairs(limits) do
    local current_usage, err = policies[conf.policy].usage(conf, api_id, identifier, current_timestamp, name)
    if err then
      return nil, nil, err
    end

    -- What is the current usage for the configured limit name?
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

local function get_period_end_in_secs(current_timestamp, limits)
  local timetable
  local periods = timestamp.get_timestamps(current_timestamp)

  for period, period_date in pairs(periods) do
    if limits[period] then
      timetable = new_from_timestamp(floor(period_date / 1000))

      -- Unfortunately 'second' & 'minute' are 'sec' and 'min' in timetable
      if period == "second" then
        timetable.sec = timetable.sec + 1

      elseif period == "minute" then
        timetable.min = timetable.min + 1

      else
        timetable[period] = timetable[period] + 1
      end
    end
  end

  -- Mutates the current object's time and date components so that are integers within 'normal' ranges
  timetable:normalise()
  return timetable:timestamp()
end

function RateLimitingHandler:new()
  RateLimitingHandler.super.new(self, "rate-limiting")
end

function RateLimitingHandler:access(conf)
  RateLimitingHandler.super.access(self)
  local current_timestamp = timestamp.get_utc()

  -- Consumer is identified by ip address or authenticated_credential id
  local identifier = get_identifier(conf)
  local api_id = ngx.ctx.api.id
  local policy = conf.policy
  local fault_tolerant = conf.fault_tolerant

  -- Load current metric for configured period
  local limits = {
    second = conf.second,
    minute = conf.minute,
    hour = conf.hour,
    day = conf.day,
    month = conf.month,
    year = conf.year
  }

  local usage, stop, err = get_usage(conf, api_id, identifier, current_timestamp, limits)
  if err then
    if fault_tolerant then
      ngx_log(ngx.ERR, "failed to get usage: ", tostring(err))
    else
      return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
    end
  end

  if usage then
    -- Adding headers
    for k, v in pairs(usage) do
      ngx.header[RATELIMIT_LIMIT .. "-" .. k] = v.limit
      ngx.header[RATELIMIT_REMAINING .. "-" .. k] = math.max(0, (stop == nil or stop == k) and v.remaining - 1 or v.remaining) -- -increment_value for this current request
    end

    -- Add X-RateLimit-Reset header (timestamp in UTC epoch seconds, for when to retry).
    ngx.header[RATELIMIT_RESET] = get_period_end_in_secs(current_timestamp, limits)

    -- If limit is exceeded, terminate the request
    if stop then
      return responses.send(429, "API rate limit exceeded")
    end
  end

  local incr = function(premature, conf, limits, api_id, identifier, current_timestamp, value)
    if premature then
      return
    end
    policies[policy].increment(conf, limits, api_id, identifier, current_timestamp, value)
  end

  -- Increment metrics for configured periods if the request goes through
  local ok, err = ngx_timer_at(0, incr, conf, limits, api_id, identifier, current_timestamp, 1)
  if not ok then
    ngx_log(ngx.ERR, "failed to create timer: ", err)
  end
end

return RateLimitingHandler
