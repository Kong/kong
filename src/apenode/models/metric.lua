-- Copyright (C) Mashape, Inc.

local Object = require "classic"
local utils = require "apenode.tools.utils"

local AVAILABLE_PERIODS = {
  second = true,
  minute = true,
  hour = true,
  day = true,
  month = true,
  year = true
}

local function check_period(period, t)
  if AVAILABLE_PERIODS[period] then
    return true
  else
    return false, "Invalid period"
  end
end

local COLLECTION = "metrics"
local SCHEMA = {
  api_id = { type = "id", required = true, },
  application_id = { type = "id" },
  origin_ip = { type = "string" },
  name = { type = "string", required = true },
  period = { type = "string", required = true, func = check_period },
  timestamp = { type = "timestamp", required = true },
  value = { type = "number", required = true }
}

local Metric = Object:extend()
Metric["_COLLECTION"] = COLLECTION
Metric["_SCHEMA"] = SCHEMA

function Metric:new(t, dao_factory)
  self._dao_factory = dao_factory
  self._t = t
end

function Metric:increment_self(step)
  if not step then step = 1 end

  if not self._t.application_id and not self._t.origin_ip then
    return false, "You need to specify at least an application_id or an ip address"
  end

  local time
  if ngx then
    time = ngx.now() -- This is optimized when it runs inside nginx
  else
    time = os.time() -- This is a syscall, thus slower
  end

  local timestamps = utils.get_timestamps(time)
  local successes = true
  local errors = {}
  for period, timestamp in pairs(timestamps) do
    local success, err = self._dao_factory[COLLECTION]:increment(self._t.api_id, self._t.application_id, self._t.origin_ip, self._t.name, timestamp, period, step)
    if err then
      successes = false
      table.insert(errors, err)
    end
  end

  if successes then
    return true
  else
    return false, errors
  end
end

function Metric.increment(api_id, application_id, origin_ip, name, step, dao_factory)
  local metric = Metric({
    name = name,
    api_id = api_id,
    application_id = application_id,
    origin_ip = origin_ip
  }, dao_factory)

  return metric:increment_self(step)
end

function Metric.find_one(args, dao_factory)
  return dao_factory[COLLECTION]:find_one(args)
end

function Metric.find(args, page, size, dao_factory)
  return dao_factory[COLLECTION]:find(args, page, size)
end

return Metric
