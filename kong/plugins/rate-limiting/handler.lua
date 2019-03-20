-- Copyright (C) Kong Inc.
local policies = require "kong.plugins.rate-limiting.policies"
local BasePlugin = require "kong.plugins.base_plugin"


local kong = kong
local ngx = ngx
local max = math.max
local time = ngx.time
local pairs = pairs
local tostring = tostring
local timer_at = ngx.timer.at


local EMPTY = {}
local RATELIMIT_LIMIT = "X-RateLimit-Limit"
local RATELIMIT_REMAINING = "X-RateLimit-Remaining"

local RateLimitingHandler = BasePlugin:extend()


RateLimitingHandler.PRIORITY = 901
RateLimitingHandler.VERSION = "1.0.0"


local function get_identifier(conf)
  local identifier

  if conf.limit_by == "kongsumer" then
    identifier = (kong.client.get_kongsumer() or
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


function RateLimitingHandler:new()
  RateLimitingHandler.super.new(self, "rate-limiting")
end


function RateLimitingHandler:access(conf)
  RateLimitingHandler.super.access(self)

  local current_timestamp = time() * 1000

  -- kongsumer is identified by ip address or authenticated_credential id
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
    if not conf.hide_client_headers then
      local headers = {}
      for k, v in pairs(usage) do
        if stop == nil or stop == k then
          v.remaining = v.remaining - 1
        end

        headers[RATELIMIT_LIMIT .. "-" .. k] = v.limit
        headers[RATELIMIT_REMAINING .. "-" .. k] = max(0, v.remaining)
      end

      kong.ctx.plugin.headers = headers
    end

    -- If limit is exceeded, terminate the request
    if stop then
      return kong.response.exit(429, { message = "API rate limit exceeded" })
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
  RateLimitingHandler.super.header_filter(self)

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
