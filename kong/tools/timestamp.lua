--- Module for timestamp support.
-- Based on the LuaTZ module.
-- @copyright Copyright 2016-2020 Kong Inc. All rights reserved.
-- @license [Apache 2.0](https://opensource.org/licenses/Apache-2.0)
-- @module kong.tools.timestamp

local luatz = require "luatz"
local tz_time = luatz.time
local tt_from_timestamp = luatz.timetable.new_from_timestamp
local tt = luatz.timetable.new
local math_floor = math.floor

--- Current UTC time
-- @return UTC time in milliseconds since epoch, but with SECOND precision.
local function get_utc()
  return math_floor(tz_time()) * 1000
end

--- Current UTC time
-- @return UTC time in milliseconds since epoch.
local function get_utc_ms()
  return tz_time() * 1000
end

-- setup a validation value, any value above this is assumed to be in MS
-- instead of S (a year value beyond the year 20000), it assumes current times
-- as in 2016 and later.
local ms_check = tt(20000 , 1 , 1 , 0 , 0 , 0):timestamp()

-- Returns a time-table.
-- @param now (optional) time to generate the time-table from. If omitted
-- current utc will be used. It can be specified either in seconds or
-- milliseconds, it will be converted automatically.
local function get_timetable(now)
  local timestamp = now and now or get_utc()
  if timestamp > ms_check then
    return tt_from_timestamp(timestamp/1000)
  end
  return tt_from_timestamp(timestamp)
end

--- Creates a timestamp table containing time by different precision levels.
-- @param now (optional) Time to generate timestamps from, if omitted current UTC time will be used
-- @return Timestamp table containing fields/precisions; second, minute, hour, day, month, year
local function get_timestamps(now)
  local timetable = get_timetable(now)
  local stamps = {}

  timetable.sec = math_floor(timetable.sec)   -- reduce to second precision
  stamps.second = timetable:timestamp() * 1000

  timetable.sec = 0
  stamps.minute = timetable:timestamp() * 1000

  timetable.min = 0
  stamps.hour = timetable:timestamp() * 1000

  timetable.hour = 0
  stamps.day = timetable:timestamp() * 1000

  timetable.day = 1
  stamps.month = timetable:timestamp() * 1000

  timetable.month = 1
  stamps.year = timetable:timestamp() * 1000

  return stamps
end

return {
  get_utc = get_utc,
  get_utc_ms = get_utc_ms,
  get_timetable = get_timetable,
  get_timestamps = get_timestamps,
}
