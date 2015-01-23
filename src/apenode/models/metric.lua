-- Copyright (C) Mashape, Inc.

local utils = require "apenode.tools.utils"
local BaseModel = require "apenode.models.base_model"

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
  application_id = { type = "id", required = false },
  origin_ip = { type = "string", required = false },
  name = { type = "string", required = true },
  period = { type = "string", required = true, func = check_period },
  timestamp = { type = "timestamp", required = true },
  value = { type = "number", required = true }
}

local Metric = BaseModel:extend()
Metric["_COLLECTION"] = COLLECTION
Metric["_SCHEMA"] = SCHEMA

function Metric:new(t, dao_factory)
  return Metric.super.new(self, COLLECTION, SCHEMA, t, dao_factory)
end

function Metric.find_one(args, dao_factory)
  local data, err =  Metric.super._find_one(args, dao_factory[COLLECTION])
  if data then
    data = Metric(data, dao_factory)
  end
  return data, err
end

function Metric.find(args, page, size, dao_factory)
  local data, total, err = Metric.super._find(args, page, size, dao_factory[COLLECTION])
  if data then
    for i,v in ipairs(data) do
      data[i] = Metric(v, dao_factory)
    end
  end
  return data, total, err
end

function Metric:increment_self(step)
  if not step then step = 1 end
  local time
  if ngx then
    time = ngx.now() -- This is optimized when it runs inside nginx
  else
    time = os.time() -- This is a syscall, thus slower
  end

  local timestamps = utils.get_timestamps(time)
  local success, err
  for period,timestamp in pairs(timestamps) do
    success, err = self._dao:increment(self.api_id, self.application_id, self.origin_ip, self.name, self.timestamp, self.period, step)
  end

  if err then
    return false, err
  else
    return true, nil
  end
end

function Metric.increment(api_id, application_id, origin_ip, name, step, dao_factory)
  if application_id == nil and origin_ip == nil then
    return false, "You need to specify at least an application_id or an ip address"
  end

  local time
  if ngx then
    time = ngx.now() -- This is optimized when it runs inside nginx
  else
    time = os.time() -- This is a syscall, thus slower
  end

  local timestamps = utils.get_timestamps(time)
  local err
  for period,timestamp in pairs(timestamps) do
    local success, e = dao_factory[COLLECTION]:increment(api_id, application_id, origin_ip, name, timestamp, period, step)
    if not success then
      err = e
    end
  end

  if err then
    return false, err
  else
    return true, nil
  end
end

return Metric
