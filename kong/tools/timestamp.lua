--
-- Module for timestamp support.
-- Based on the LuaTZ module.
local luatz = require "luatz"
local _M = {}

--- Current UTC time
-- @return UTC time
function _M.get_utc()
  return math.floor(luatz.time()) * 1000
end

function _M.get_timetable(now)
  local timestamp = now and now or _M.get_utc()
  if string.len(tostring(timestamp)) == 13 then
    timestamp = timestamp / 1000
  end
  return luatz.timetable.new_from_timestamp(timestamp)
end

--- Creates a timestamp
-- @param now (optional) Time to generate a timestamp from, if omitted current UTC time will be used
-- @return Timestamp table containing fields; second, minute, hour, day, month, year
function _M.get_timestamps(now)
  local timetable = _M.get_timetable(now)

  local second = luatz.timetable.new(timetable.year, timetable.month,
                                     timetable.day, timetable.hour,
                                     timetable.min, timetable.sec)

  local minute = luatz.timetable.new(timetable.year, timetable.month,
                                     timetable.day, timetable.hour,
                                     timetable.min, 0)

  local hour = luatz.timetable.new(timetable.year, timetable.month,
                                   timetable.day, timetable.hour,
                                   0, 0)

  local day = luatz.timetable.new(timetable.year, timetable.month,
                                  timetable.day, 0, 0, 0)

  local month = luatz.timetable.new(timetable.year, timetable.month,
                                    1, 0, 0, 0)

  local year = luatz.timetable.new(timetable.year, 1, 1, 0, 0, 0)

  return {
    second = math.floor(second:timestamp() * 1000),
    minute = minute:timestamp() * 1000,
    hour = hour:timestamp() * 1000,
    day = day:timestamp() * 1000,
    month = month:timestamp() * 1000,
    year = year:timestamp() * 1000
  }
end

return _M
